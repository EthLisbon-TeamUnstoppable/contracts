// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
import './IJudgeManager.sol';

struct CaseParticipant {
	address addr;
	bytes32 proofHash;
	string proof;
	uint collateral;
}

enum CaseStates {
	Undefined,
	Requested,
	Accepted,
	DisclosingProofs,
	Judging,
	Won,
	Lost,
	Aborted,
	Closed
}

struct CaseData {
	CaseParticipant requester;	
	CaseParticipant opponent;
	address[] judges;
	uint judgesRequired;
	string description;

	CaseStates state;
	uint tally;
	uint votes;
	uint baseCollateral;
	uint expiration;
}

contract Case {
	uint constant STEP_EXPIRATION_TIME = 30 seconds; //1 days;
	uint constant JUDGE_CUT_DENOMINATOR = 100000; // 100%
	uint constant JUDGE_CUT = 1000; // 1%

	CaseData data;
	
	mapping (address => bool) isJudgeVoteRequired;

	IJudgeManager judges;

	event CaseRequested(address indexed requester, address indexed opponent);
	event CaseAccepted(address indexed requester, address indexed opponent);
	event JudgeAssigned(address indexed judge, uint caseId);
	event CaseAborted();
	event CaseClosed();

	constructor(IJudgeManager judgesContract, address requesterAddress, address opponentAddress, string memory description, bytes32 proofHash, uint collateral) payable {
		require(msg.value == collateral, "Invalid collateral provided");

		judges = judgesContract;
		data = CaseData(
			CaseParticipant(requesterAddress, proofHash, "", collateral),
			CaseParticipant(opponentAddress, "", "", 0),
			new address[](0),
			1,
			description,
			CaseStates.Requested,
			0,
			0,
			collateral,
			block.timestamp + STEP_EXPIRATION_TIME
		);

		emit CaseRequested(requesterAddress, opponentAddress);
	}

	function getCaseData() public view returns (CaseData memory) {
		return data;
	}

	function isExpired() public view returns (bool) {
		return data.expiration < block.timestamp;
	}

	function isRequester(address addr) public view returns (bool) {
		return data.requester.addr == addr;
	}
	
	function isOpponent(address addr) public view returns (bool) {
		return data.opponent.addr == addr;
	}

	function isJudge(address addr) public view returns (bool) {
		for (uint256 index = 0; index < data.judges.length; index++) {
			if (data.judges[index] == addr) {
				return true;
			}
		}
		return false;
	}

	function needsJudges() public view returns (bool) {
		return data.state == CaseStates.Judging && data.judges.length < data.judgesRequired;
	}

	modifier onlyJudgesContract {
		require(msg.sender == address(judges), "Invalid function call");
		_;
	}

	modifier handlesExpired {
		if (isExpired()) {
			handleExpiredCase();
		} else {
			_;
		}
	}

	modifier bumpsExpiration {
		_;
		data.expiration = block.timestamp + STEP_EXPIRATION_TIME;
	}

	function acceptCase(bytes32 proofHash) public payable handlesExpired bumpsExpiration onlyJudgesContract {
		require(data.state == CaseStates.Requested);
		require(data.baseCollateral == msg.value, "Provide the right amount of collateral");

		data.opponent.proofHash = proofHash;
		data.opponent.collateral = data.baseCollateral;
		data.state = CaseStates.Accepted;

		emit CaseAccepted(data.requester.addr, data.opponent.addr);
	}

	function discloseRequesterProof(string calldata proof) public handlesExpired bumpsExpiration onlyJudgesContract {
		require(data.state == CaseStates.Accepted || data.state == CaseStates.DisclosingProofs, "This case does not accept proofs");
		require(!isDisclosedProof(data.requester), "The proof is already provided");
		require(keccak256(abi.encodePacked(proof)) == data.requester.proofHash, "Proof does not match proof hash");
		
		data.requester.proof = proof;
		data.state = CaseStates(uint(data.state) + 1); // move on to next state (either Disclosing or Judging)
	}

	function discloseOpponentProof(string calldata proof) public handlesExpired bumpsExpiration onlyJudgesContract {
		require(data.state == CaseStates.Accepted || data.state == CaseStates.DisclosingProofs, "This case does not accept proofs");
		require(!isDisclosedProof(data.opponent), "The proof is already provided");
		require(keccak256(abi.encodePacked(proof)) == data.opponent.proofHash, "Proof does not match proof hash");
		
		data.opponent.proof = proof;
		data.state = CaseStates(uint(data.state) + 1); // move on to next state (either Disclosing or Judging)
	}
	
	function assignJudge(address judgeAddress) public handlesExpired onlyJudgesContract returns (bool) {
		if (data.state == CaseStates.Judging && !isJudge(judgeAddress)) { // Don't fail for other states to allow calling multiple times
			isJudgeVoteRequired[judgeAddress] = true;
			data.judges.push(judgeAddress);
			return true;
		}
		return false;
	}

	function setDecision(bool win, address judge) public handlesExpired bumpsExpiration onlyJudgesContract {
		require(data.state == CaseStates.Judging, "This case is not being judged");
		require(isJudgeVoteRequired[judge], "This judge has voted");

		if (win) {
			data.tally += 1;
		}
		isJudgeVoteRequired[judge] = false;
		data.votes += 1;

		if (data.votes == data.judgesRequired) {
			if(data.tally >= data.judgesRequired / 2) {
				data.state = CaseStates.Won;
			} else {
				data.state = CaseStates.Lost;
			}
		}

		judges.reportGood(judge);
	}

	function appeal(address appealer) public payable handlesExpired bumpsExpiration onlyJudgesContract {
		require(data.state == CaseStates.Won || data.state == CaseStates.Lost, "The case cannot be appealed");
		require(msg.value == data.baseCollateral * 3);

		if (data.requester.addr == appealer) {
			data.requester.collateral += msg.value;
		} else if (data.opponent.addr == appealer) {
			data.opponent.collateral += msg.value;
		}
		data.baseCollateral *= 3;
		data.judgesRequired *= 3;
		data.judges = new address[](0);
		data.tally = 0;
		data.votes = 0;
		data.state = CaseStates.Judging;
	}
	
	function claim() public {
		require(isExpired(), "The case is not expired");
		handleExpiredCase(); // win or lose, either way someone has to receive money
	}

	function isDisclosedProof(CaseParticipant storage participant) private view returns (bool) {
		return bytes(participant.proof).length > 0;
	}

	function refundAll() private {
		if (data.requester.collateral != 0) {
			payable(data.requester.addr).transfer(data.requester.collateral);
		}

		if (data.opponent.collateral != 0) {
			payable(data.opponent.addr).transfer(data.opponent.collateral);
		}
	}

	function sendJudgeCut(uint losersCollateral) private {
		uint judgesCut = losersCollateral * JUDGE_CUT / JUDGE_CUT_DENOMINATOR;
		for (uint256 index = 0; index < data.judges.length; index++) {
			payable(data.judges[index]).transfer(judgesCut); // send the judge their cut
		}
	}

	function handleExpiredCase() private {
		if (data.state == CaseStates.Requested || data.state == CaseStates.Accepted) {
			data.state = CaseStates.Aborted;
			refundAll();
			emit CaseAborted();
			
		} else if (data.state == CaseStates.DisclosingProofs) { // only one of participants disclosed proof
			// send everything to the one who disclosed proof
			address goodBoy = address(0x0);
			if (isDisclosedProof(data.opponent)) {
				goodBoy = data.opponent.addr;
			} else if (isDisclosedProof(data.requester)) {
				goodBoy = data.requester.addr;
			}

			data.state = CaseStates.Aborted;
			payable(goodBoy).transfer(address(this).balance);
			emit CaseAborted();
						
		} else if (data.state == CaseStates.Judging) { // Judging did not complete on time
			// refund both and report the bad judges
			data.state = CaseStates.Aborted;
			refundAll();
			for (uint256 index = 0; index < data.judges.length; index++) {
				if (isJudgeVoteRequired[data.judges[index]]) {
					judges.reportBad(data.judges[index]);
				}
			}
			emit CaseAborted();
		} else if (data.state == CaseStates.Won) { // requester wins
			data.state = CaseStates.Closed;
			sendJudgeCut(data.opponent.collateral);
			payable(data.requester.addr).transfer(address(this).balance); // send the rest to the requester
			emit CaseClosed();
		} else if (data.state == CaseStates.Lost) { // requester loses, opponent wins
			data.state = CaseStates.Closed;
			sendJudgeCut(data.requester.collateral);
			payable(data.opponent.addr).transfer(address(this).balance); // send the rest to the opponent
			emit CaseClosed();
		}
	}
}
