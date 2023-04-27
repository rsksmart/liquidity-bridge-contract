const Web3 = require("web3");

module.exports = function (callback) {
  const json = require("../build/contracts/LiquidityBridgeContract.json");
  let accounts;
  // in web front-end, use an onload listener and similar to this manual flow ...
  web3.eth.getAccounts(function (err, res) {
    accounts = res;
  });

  const contract = new web3.eth.Contract(
    json.abi,
    "0xcdC617a31a5819dA29ebcf0Fa96352d62D354d18"
  );

  contract.methods
    .register(
      "First contract",
      10,
      7200,
      3600,
      10,
      100,
      "http://localhost/api",
      true,
      "both"
    )
    .call({
      // from: accounts[0],
      value: 100000000000000000,
    })
    .then((response) => console.log("Success: " + response))
    .catch((err) => console.log("Error: " + err));

  // invoke callback
  callback();
};
