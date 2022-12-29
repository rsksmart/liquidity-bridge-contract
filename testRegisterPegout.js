const Web3 = require("web3");
const web3Provider = new Web3.providers.HttpProvider('http://localhost:4444');

const web3 = new Web3(web3Provider);
web3.eth.handleRevert = true
const json = require("./build/contracts/LiquidityBridgeContract.json");

const contract = new web3.eth.Contract(json.abi, "0x1Af2844A588759D0DE58abD568ADD96BB8B3B6D8");

const quotePegOutRegister = {
	"lbcAddress": "0x1Af2844A588759D0DE58abD568ADD96BB8B3B6D8",
	"liquidityProviderRskAddress": "0x9D93929A9099be4355fC2389FbF253982F9dF47c",
	"rskRefundAddress": "0xa554d96413FF72E93437C4072438302C38350EE3",
	"fee": 1000,
	"penaltyFee": 1000000,
	"nonce": "8572757636462532616",
	"valueToTransfer": 200,
	"agreementTimestamp": 1671742578,
	"depositDateLimit": 3600,
	"depositConfirmations": 2,
	"transferConfirmations": 0,
	"transferTime": 0,
	"expireDate": 1671746178,
	"expireBlocks": 5495
}



const sig = Web3.utils.hexToBytes("0x"+"7869400876f1f56f2d7f926961ac98476dc51ba507b1c403690a348e2bd88bab64ec265ce63186aec7afb8f862db919707fe0f23c2ee7e1d033fc51e3403e48b1c");

contract.methods.registerPegOut(quotePegOutRegister, Buffer.from(sig)).send({from: "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",value: "1200", gas: "900000"}).then(console.log)