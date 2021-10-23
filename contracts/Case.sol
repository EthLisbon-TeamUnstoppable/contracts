// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
import './IJudgeManager.sol';

contract Case {
	uint constant STEP_EXPIRATION_TIME = 30 seconds; //1 days;
	uint constant JUDGE_CUT_DENOMINATOR = 100000; // 100%
	uint constant JUDGE_CUT = 1000; // 1%

	struct CaseParticipant {
		address addr;
		bytes32 proofHash;
		string proof;
		uint collateral;
	}

	address judge;
	CaseParticipant requester;	
	CaseParticipant opponent;

	uint baseCollateral;
	uint expiration;

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

	CaseStates state;
	IJudgeManager judges;

	event CaseRequested(address indexed requester, address indexed opponent);
	event CaseAccepted(address indexed requester, address indexed opponent);
	event JudgeAssigned(address indexed judge, uint caseId);
	event CaseAborted();
	event CaseClosed();

	constructor(IJudgeManager judgesContract, address requesterAddress, address opponentAddress, bytes32 proofHash, uint collateral) payable {
		judges = judgesContract;
		baseCollateral = collateral;
		requester = CaseParticipant(requesterAddress, proofHash, "", collateral);
		opponent = CaseParticipant(opponentAddress, "", "", 0);
		expiration = block.timestamp + STEP_EXPIRATION_TIME;
		state = CaseStates.Requested;

		emit CaseRequested(requesterAddress, opponentAddress);
	}

	function isExpired() public view returns (bool) {
		return expiration < block.timestamp;
	}

	function isRequester(address addr) public view returns (bool) {
		return requester.addr == addr;
	}
	
	function isOpponent(address addr) public view returns (bool) {
		return opponent.addr == addr;
	}

	function isJudge(address addr) public view returns (bool) {
		return judge == addr;
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
		expiration = block.timestamp + STEP_EXPIRATION_TIME;
	}

	function acceptCase(bytes32 proofHash) public payable handlesExpired bumpsExpiration onlyJudgesContract {
		require(state == CaseStates.Requested);
		require(baseCollateral == msg.value, "Provide the right amount of collateral");

		opponent.proofHash = proofHash;
		opponent.collateral = baseCollateral;
		state = CaseStates.Accepted;

		emit CaseAccepted(requester.addr, opponent.addr);
	}

	function discloseRequesterProof(string calldata proof) public handlesExpired bumpsExpiration onlyJudgesContract {
		require(state == CaseStates.Accepted || state == CaseStates.DisclosingProofs, "This case does not accept proofs");
		require(!isDisclosedProof(requester), "The proof is already provided");
		require(keccak256(abi.encodePacked(proof)) == requester.proofHash, "Proof does not match proof hash");
		
		requester.proof = proof;
		state = CaseStates(uint(state) + 1); // move on to next state (either Disclosing or Judging)
	}

	function discloseOpponentProof(string calldata proof) public handlesExpired bumpsExpiration onlyJudgesContract {
		require(state == CaseStates.Accepted || state == CaseStates.DisclosingProofs, "This case does not accept proofs");
		require(!isDisclosedProof(opponent), "The proof is already provided");
		require(keccak256(abi.encodePacked(proof)) == opponent.proofHash, "Proof does not match proof hash");
		
		opponent.proof = proof;
		state = CaseStates(uint(state) + 1); // move on to next state (either Disclosing or Judging)
	}
	
	function assignJudge(address judgeAddress) public handlesExpired onlyJudgesContract {
		if (state == CaseStates.Judging) { // Don't fail for other states to allow calling multiple times
			judge = judgeAddress;
		}
	}

	function setDecision(bool win) public handlesExpired bumpsExpiration onlyJudgesContract {
		require(state == CaseStates.Judging, "This case is not being judged");

		if (win) {
			state = CaseStates.Won;
		} else {
			state = CaseStates.Lost;
		}

		judges.reportGood(judge);
	}

	function appeal(address appealer) public payable handlesExpired bumpsExpiration onlyJudgesContract {
		require(state == CaseStates.Won || state == CaseStates.Lost, "The case cannot be appealed");
		require(msg.value == baseCollateral * 3);

		if (requester.addr == appealer) {
			requester.collateral += msg.value;
		} else if (opponent.addr == appealer) {
			opponent.collateral += msg.value;
		}
		baseCollateral *= 3;
		state = CaseStates.Judging;
	}
	
	function claim() public {
		require(isExpired(), "The case is not expired");
		handleExpiredCase(); // win or lose, either way someone has to receive money
	}

	function isDisclosedProof(CaseParticipant storage participant) private view returns (bool) {
		return bytes(participant.proof).length > 0;
	}

	function refundAll() private {
		if (requester.collateral != 0) {
			payable(requester.addr).transfer(requester.collateral);
		}

		if (opponent.collateral != 0) {
			payable(opponent.addr).transfer(opponent.collateral);
		}
	}

	function sendJudgeCut(uint losersCollateral) private {
		uint judgesCut = losersCollateral * JUDGE_CUT / JUDGE_CUT_DENOMINATOR;
		payable(judge).transfer(judgesCut); // send the judge their cut
	}

	function handleExpiredCase() private {
		if (state == CaseStates.Requested || state == CaseStates.Accepted) {
			state = CaseStates.Aborted;
			refundAll();
			emit CaseAborted();
			
		} else if (state == CaseStates.DisclosingProofs) { // only one of participants disclosed proof
			// send everything to the one who disclosed proof
			address goodBoy = address(0x0);
			if (isDisclosedProof(opponent)) {
				goodBoy = opponent.addr;
			} else if (isDisclosedProof(requester)) {
				goodBoy = requester.addr;
			}

			state = CaseStates.Aborted;
			payable(goodBoy).transfer(address(this).balance);
			emit CaseAborted();
						
		} else if (state == CaseStates.Judging) { // Judging did not complete on time
			// refund both and report the bad judges
			state = CaseStates.Aborted;
			refundAll();
			judges.reportBad(judge);
			emit CaseAborted();
		} else if (state == CaseStates.Won) { // requester wins
			state = CaseStates.Closed;
			sendJudgeCut(opponent.collateral);
			payable(requester.addr).transfer(address(this).balance); // send the rest to the requester
			emit CaseClosed();
		} else if (state == CaseStates.Lost) { // requester loses, opponent wins
			state = CaseStates.Closed;
			sendJudgeCut(requester.collateral);
			payable(opponent.addr).transfer(address(this).balance); // send the rest to the opponent
			emit CaseClosed();
		}
	}
}
