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

  it('should judge', async () => {
    await cryptoJudgesInstance.createCase(opponent, "0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658", {from: requester, value: web3.utils.toBN('100')});
    await cryptoJudgesInstance.acceptCase(1, "0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658", {from: opponent, value: web3.utils.toBN('100')});
    await cryptoJudgesInstance.discloseProof(1, "test", {from: requester});
    await cryptoJudgesInstance.discloseProof(1, "test", {from: opponent});
    await cryptoJudgesInstance.setDecision(1, true, {from: judge});
    await sleep(35000);
    await cryptoJudgesInstance.claim(1, {from: requester});
    assert(false); // to see contract logs
  });
});
