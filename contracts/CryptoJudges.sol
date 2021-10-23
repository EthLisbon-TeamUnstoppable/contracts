// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
import './IJudgeManager.sol';
import './Case.sol';

contract CryptoJudges is IJudgeManager {
	struct Judge {
		address addr;
		uint score;
		uint stake;
		bool banned;
	}

	mapping (uint => Judge) JudgesData;
	mapping (address => uint) Judges;
	uint currentJudgeId;
	mapping (uint => Case) Cases;
	uint currentCaseId;

	uint constant REQUIRED_JUDGE_STAKE = 100; //1 ether;
	uint constant MINIMUM_CASE_COLLATERAL = 1; //gwei;
	uint constant JUDGE_SCORE_INITIAL = 100;
	uint constant JUDGE_SCORE_INCREMENT = 10;
	uint constant JUDGE_SCORE_DECREMENT = 20;

	constructor() {
		currentJudgeId = 0; // id == 0 -> null judge/case/request
		currentCaseId = 0;
	}

	//////
	// Judge management
	//////

	function registerJudge() public payable {
		require(Judges[msg.sender] == 0, "This address is already a judge");
		require(msg.value == REQUIRED_JUDGE_STAKE, "Invalid stake provided");

		currentJudgeId++;
		JudgesData[currentJudgeId] = Judge(msg.sender, JUDGE_SCORE_INITIAL, REQUIRED_JUDGE_STAKE, false);
		Judges[msg.sender] = currentJudgeId;
	}

	function reportGood(address judge) public {
		JudgesData[Judges[judge]].score += JUDGE_SCORE_INCREMENT;
	}

	function reportBad(address judge) public {
		uint judgeId = Judges[judge];
		if (JudgesData[judgeId].score < JUDGE_SCORE_DECREMENT) { // score is too low, kick the judge
			JudgesData[judgeId].banned = true;
			payable(address(0x0)).transfer(JudgesData[judgeId].stake);
		}
		JudgesData[judgeId].score -= JUDGE_SCORE_DECREMENT;
	}

	//////
	// Case management
	//////

	function createCase(address opponent, bytes32 proofHash) public payable returns (uint caseId) {
		require(Judges[msg.sender] == 0, "A judge cannot open a case");
		require(Judges[opponent] == 0, "A judge cannot be an opponent");
		require(msg.value >= MINIMUM_CASE_COLLATERAL, "Must provide some coins as collateral");

		currentCaseId++;
		Case newCase = (new Case){value:msg.value}(
			this,
			msg.sender,
			opponent,
			proofHash,
			msg.value);
		Cases[currentCaseId] = newCase;

		return currentCaseId;
	}

	function caseContract(uint caseId) public view returns (address) {
		return address(Cases[caseId]);
	}

	function acceptCase(uint caseId, bytes32 proofHash) public payable {
		require(Cases[caseId].isOpponent(msg.sender), "This is not your case");
		
		Cases[caseId].acceptCase{value:msg.value}(proofHash);
	}

	function discloseProof(uint caseId, string calldata proof) public {
		if (Cases[caseId].isRequester(msg.sender)) {
			Cases[caseId].discloseRequesterProof(proof);
		} else if (Cases[caseId].isOpponent(msg.sender)) {
			Cases[caseId].discloseOpponentProof(proof);
		} else {
			revert("You are not related to this case");
		}

		assignJudge(caseId);
	}

	function setDecision(uint caseId, bool win) public {
		require(Cases[caseId].isJudge(msg.sender), "You are not the judge");
		Cases[caseId].setDecision(win);
	}

	function appeal(uint caseId) public payable {
		require(Cases[caseId].isRequester(msg.sender) || Cases[caseId].isOpponent(msg.sender), "You are not related to this case");
		
		Cases[caseId].appeal{value:msg.value}(msg.sender);
		assignJudge(caseId);
	}

	function claim(uint caseId) public {
		Cases[caseId].claim();
	}

	function assignJudge(uint caseId) private {
		uint judge = 0;
		while (judge == 0 || JudgesData[judge].banned) { // keep rolling untill we find a judge
			judge = (uint(keccak256(abi.encodePacked(blockhash(block.number - 1)))) % currentJudgeId) + 1;
		}
		Cases[caseId].assignJudge(JudgesData[judge].addr); // no-op if not ready to assign
	}
}
