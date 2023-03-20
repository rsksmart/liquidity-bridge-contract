const { upgradeProxy } = require("@openzeppelin/truffle-upgrades");

// const version = "V2";

// const SignatureValidator = artifacts.require("SignatureValidator");
// const LiquidityBridgeContract = artifacts.require(`LiquidityBridgeContract`);
// const LiquidityBridgeContractUpgrade = artifacts.require(
//   `LiquidityBridgeContract${version}`
// );

// const { deploy, read } = require("../config");

// module.exports = async function (deployer, network) {
//   let config = read();
//   config = await deploy("LiquidityBridgeContract", network, async (state) => {
//     const signatureValidatorLib = await SignatureValidator.at(
//       config[network]["SignatureValidator"].address
//     );
//     await deployer.link(signatureValidatorLib, LiquidityBridgeContractUpgrade);

//     const existing = await LiquidityBridgeContract.deployed();
//     const response = await upgradeProxy(
//       existing.address,
//       LiquidityBridgeContractUpgrade,
//       { deployer, unsafeAllowLinkedLibraries: true }
//     );
//     console.log("Upgraded", response.address);
//     state.address = response.address;
//   });
// };
