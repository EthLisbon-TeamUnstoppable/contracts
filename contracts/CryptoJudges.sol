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
	mapping (address => uint) lastCases;
	uint currentCaseId;

	uint constant REQUIRED_JUDGE_STAKE = 100000 gwei; // 0.0001 ether;
	uint constant MINIMUM_CASE_COLLATERAL = 1 gwei; //gwei;
	uint constant JUDGE_SCORE_INITIAL = 100;
	uint constant JUDGE_SCORE_INCREMENT = 10;
	uint constant JUDGE_SCORE_DECREMENT = 50;

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
		require (msg.sender == address(Cases[lastCases[judge])])
		JudgesData[Judges[judge]].score += JUDGE_SCORE_INCREMENT;
	}

	function reportBad(address judge) public {
		require (msg.sender == address(Cases[lastCases[judge])])
		uint judgeId = Judges[judge];
		if (JudgesData[judgeId].score < JUDGE_SCORE_DECREMENT) { // score is too low, kick the judge
			JudgesData[judgeId].banned = true;
			payable(address(0x0)).transfer(JudgesData[judgeId].stake);
			return;
		}
		JudgesData[judgeId].score -= JUDGE_SCORE_DECREMENT;
	}

	//////
	// Case management
	//////

	function createCase(address opponent, string calldata description, bytes32 proofHash) public payable returns (uint caseId) {
		require(Judges[msg.sender] == 0, "A judge cannot open a case");
		require(Judges[opponent] == 0, "A judge cannot be an opponent");
		require(msg.value >= MINIMUM_CASE_COLLATERAL, "Must provide some coins as collateral");

		currentCaseId++;
		Case newCase = (new Case){value:msg.value}(
			this,
			currentCaseId,
			msg.sender,
			opponent,
			description,
			proofHash,
			msg.value);
		Cases[currentCaseId] = newCase;

		lastCases[msg.sender] = currentCaseId;
		lastCases[opponent] = currentCaseId;

		return currentCaseId;
	}

	function getCase(address participant) public view returns (CaseData memory) {
		require(lastCases[participant] != 0, "No cases");
		
		return Cases[lastCases[participant]].getCaseData();
	}
	
	function getCaseById(uint caseId) public view returns (CaseData memory) {
		require(address(Cases[caseId]) != address(0x0), "No case");
		return Cases[caseId].getCaseData();
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
		Cases[caseId].setDecision(win, msg.sender);
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
		while (Cases[caseId].needsJudges()) {
			uint judge = 0;
			while (judge == 0 || JudgesData[judge].banned || Cases[caseId].isJudge(JudgesData[judge].addr)) { // keep rolling untill we find a judge
				judge = (uint(keccak256(abi.encodePacked(blockhash(block.number - 1)))) % currentJudgeId) + 1;
			}
			if (Cases[caseId].assignJudge(JudgesData[judge].addr)) {
				lastCases[JudgesData[judge].addr] = caseId;
			}
		}
	}
}
