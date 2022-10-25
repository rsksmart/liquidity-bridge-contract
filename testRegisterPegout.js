const Web3 = require("web3");
const bs58 = require("bs58");
var BN = Web3.utils.BN;

const toHex = hash => {
    const b = bs58.decode(hash);
    return b;
};

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

const json = require("./build/contracts/LiquidityBridgeContract.json");

const contract = new web3.eth.Contract(json.abi, "0xcb189e1F1cc730B4458D64fd7f0f68DcC60cbced");

const quotePegOutRegister = {
	"lbcAddress": "0xcb189e1F1cc730B4458D64fd7f0f68DcC60cbced",
	"liquidityProviderRskAddress": "0x9D93929A9099be4355fC2389FbF253982F9dF47c",
	"rskRefundAddress": "0xa554d96413FF72E93437C4072438302C38350EE3",
	"fee": "1000",
	"penaltyFee": "1000000",
	"nonce": "4862760736690061306",
	"valueToTransfer": "600000000000000000",
	"agreementTimestamp": "1666724140",
	"depositDateLimit": 3600,
	"depositConfirmations": 10,
	"transferConfirmations": 0,
	"transferTime": 0,
	"expireDate": 0,
	"expireBlocks": 0
}

function getAccounts(web3) {
	web3.eth.getAccounts().then(accounts => {
		accounts.forEach(a => web3.eth.getBalance(a).then(b => console.log(`Account ${a} Balance ${b}`)))
	})
}

function hashPegout(contract, quotePegOutRegister) {
	contract.methods.hashPegoutQuote(quotePegOutRegister).call().then(console.log)
}

const sig = Web3.utils.hexToBytes("0x"+"31405ed3c5dab19912badd558896c4565c3376fd9bb5d945114b1e03f199e7a118ec1f590ae6e0b638fcdd187507272e5ceacd4254ca538f73cb4640da57c8561b");


contract.methods.registerPegOut(quotePegOutRegister, Buffer.from(sig)).send({from: "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",value: "600000000000001000", gas: "900000"}).then(console.log)


