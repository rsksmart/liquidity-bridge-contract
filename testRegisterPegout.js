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

const contract = new web3.eth.Contract(json.abi, "0xd8B57e141b7194fB857874ab185BC99675A2332F");

const quotePegOutRegister = {
	"lbcAddress": "0xd8B57e141b7194fB857874ab185BC99675A2332F",
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

function getAccounts(web3) {
	web3.eth.getAccounts().then(accounts => {
		accounts.forEach(a => web3.eth.getBalance(a).then(b => console.log(`Account ${a} Balance ${b}`)))
	})
}

function hashPegout(contract, quotePegOutRegister) {
	contract.methods.hashPegoutQuote(quotePegOutRegister).call().then(console.log)
}

const sig = Web3.utils.hexToBytes("0x"+"227f40d739f18ce8545972056fd100a51ade084bb2076dc5128966a2683ec85578e8710d4f3c08d854b68a9aace055644928d2045173ae24329f5c55428e26c11b");


contract.methods.registerPegOut(quotePegOutRegister, Buffer.from(sig)).send({from: "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",value: "200", gas: "900000"}).then(console.log)

// contract.methods.hashPegoutQuote(quotePegOutRegister).call().then(console.log)

// afe0a4b398ef603a533b7f4751d7eb9a0ba3fdb01e71c3774383d423f944b580