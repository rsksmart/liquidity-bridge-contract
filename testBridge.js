const Web3 = require("web3");
var web3Provider = new Web3.providers.HttpProvider('http://localhost:4444');

var web3 = new Web3(web3Provider);
web3.eth.handleRevert = true;

const bridge = new web3.eth.Contract(require("./build/contracts/Bridge.json").abi, "0x0000000000000000000000000000000001000006");


const bh ="0x" + "440fd85092e1f422507b8b307e0773bb95725cfddd81d51b485d9fee11aab4c4";


const tx = "0x" + "82e2cb89e23b4cafb1a91a882db842e77da275fa6c6b4f9ca6ef0ee29caa345d";


const pmt = "1";

const mtb = [
	"0x" + "ac30ca450d5782c2523a450d077943b2d8916eeeb100ada79b7f4e9c945c2dd0",
];
bridge.methods.getBtcTransactionConfirmations(tx, bh, pmt, mtb).call()
.then(t => {
	console.log('success')
	console.log(t)
	
})
.catch(e => {
	console.log('error')
	console.log(e) });

bridge.methods.getBtcBlockchainBestChainHeight().call().then(console.log)