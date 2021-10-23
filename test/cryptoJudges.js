const CryptoJudges = artifacts.require("CryptoJudges");

contract('CryptoJudges', (accounts) => {
  let cryptoJudgesInstance;
  let judge = accounts[0];
  let requester = accounts[1];
  let opponent = accounts[2];

  beforeEach(async () => {
    cryptoJudgesInstance = await CryptoJudges.deployed();
    await cryptoJudgesInstance.registerJudge({from: judge, value: 100});
  })

  function sleep(time) {
    return new Promise(resolve => setTimeout(resolve, time));
  }

  async function logCase(id, func) {
    console.log(func);
    let casedata = await cryptoJudgesInstance.getCaseById(id);
    console.log(casedata);
    console.log(`--- ${func} ---`);
  }

  it('should judge', async () => {
    await cryptoJudgesInstance.createCase(opponent, "This is a test case", "0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658", {from: requester, value: web3.utils.toBN('100')});
    await logCase(1, "createCase");
    await cryptoJudgesInstance.acceptCase(1, "0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658", {from: opponent, value: web3.utils.toBN('100')});
    await logCase(1, "acceptCase");

    await cryptoJudgesInstance.discloseProof(1, "test", {from: requester});
    await logCase(1, "discloseProof requester");

    await cryptoJudgesInstance.discloseProof(1, "test", {from: opponent});
    await logCase(1, "discloseProof opponent");

    await cryptoJudgesInstance.setDecision(1, true, {from: judge});
    await logCase(1, "setDecision 1");

    // await cryptoJudgesInstance.appeal(1, {from: opponent, value: web3.utils.toBN('300')});
    // await logCase(1, "appeal");

    // await cryptoJudgesInstance.setDecision(1, true, {from: judge});
    // await logCase(1, "setDecision 2");

    try {
      await cryptoJudgesInstance.claim(1, {from: requester});
    } catch (error) {
      console.log(`Caught expected error: ${error}`)
    }

    await sleep(35000);
    await cryptoJudgesInstance.claim(1, {from: requester});
    await logCase(1, "claim");

    assert(false); // to see contract logs
  });
});
