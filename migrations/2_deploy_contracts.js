const CryptoJudges = artifacts.require("CryptoJudges");

module.exports = function(deployer) {
  deployer.deploy(CryptoJudges);
};
