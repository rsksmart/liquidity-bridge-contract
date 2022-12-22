const Web3 = require("web3");
const bs58 = require("bs58");
var BN = Web3.utils.BN;

const toHex = hash => {
    const b = bs58.decode(hash);
    return b;
};

const toBuffer = (value) => Buffer.from()

const toHex20 = hash => {
    const b = bs58.decode(hash);
    return b.slice(1, b.length-4);
};

const toHex21 = hash => {
    const b = bs58.decode(hash);
    return b.slice(0, b.length-4);
};
var web3Provider = new Web3.providers.HttpProvider('http://localhost:4444');

var web3 = new Web3(web3Provider);
web3.eth.handleRevert = true
const json = require("./build/contracts/LiquidityBridgeContract.json");

const contract = new web3.eth.Contract(json.abi, "0xC9dB73F54D43479b1a67DB2284bCFed17b0A13c2");

const quotePegOutRegister = {
	"lbcAddress": "0xC9dB73F54D43479b1a67DB2284bCFed17b0A13c2",
	"liquidityProviderRskAddress": "0x9D93929A9099be4355fC2389FbF253982F9dF47c",
	"rskRefundAddress": "0xa554d96413FF72E93437C4072438302C38350EE3",
	"fee": "0",
	"penaltyFee": "1000000",
	"nonce": "4838926104160593202",
	"valueToTransfer": "200",
	"agreementTimestamp": "1669989762",
	"depositDateLimit": "7200",
	"depositConfirmations": "2",
	"transferConfirmations": "0",
	"transferTime": "0",
	"expireDate": 1669996962,
	"expireBlocks": 43219
}

contract.methods.hashPegoutQuote(quotePegOutRegister).call().then(console.log)
