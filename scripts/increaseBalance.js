const Web3 = require("web3");

// const web3 = new Web3(web3Provider);
// const json = require("./build/contracts/LiquidityBridgeContract.json");

// web3.eth.accounts
//   .create(
//     "energy save odor silver mushroom topple visual summer safe angry tent spend"
//   )
//   .then((response) => {
//     console.log(response);
//   });

// //

module.exports = function (callback) {
  const json = require("../build/contracts/LiquidityBridgeContract.json");
  let accounts;
  // in web front-end, use an onload listener and similar to this manual flow ...
  web3.eth.getAccounts(function (err, res) {
    accounts = res;
  });

  console.log

  const contract = new web3.eth.Contract(
    json.abi,
    "0x759d9b28b6ca416892550996ad531020bbfa3f03"
  );

  contract.methods
    .deposit()
    .call({
      //from: "0xd053b9B695BEb7104deEa56773197F05AD03E4e0",
      value: 100000000000000000,
    })
    .then(response => console.log("Success: " + response)).catch(err => console.log("Error: " + err))

  // invoke callback
  callback();
};
