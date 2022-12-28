const Web3 = require("web3");
const web3Provider = new Web3.providers.HttpProvider('http://localhost:4444');

const web3 = new Web3(web3Provider);
web3.eth.handleRevert = true;
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


const bh ="0x" + "440fd85092e1f422507b8b307e0773bb95725cfddd81d51b485d9fee11aab4c4";


const tx = "0x" + "82e2cb89e23b4cafb1a91a882db842e77da275fa6c6b4f9ca6ef0ee29caa345d";


const pmt = "1";

const mtb = [
	"0x" + "ac30ca450d5782c2523a450d077943b2d8916eeeb100ada79b7f4e9c945c2dd0",
];

contract.methods.refundPegOut(quotePegOutRegister, tx, bh, pmt, mtb).send({from: "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826", gas: "900000"})
.then(t => {
	console.log('success')
	console.log(t)
	
});
contract.methods.getProcessedQuote(Buffer.from(Web3.utils.hexToBytes("0x" + "8089169d67d7c6730f7fb8db0cfdf946f91c30ab8001d27370a6e4efc5e03179"))).call().then(console.log)
contract.methods.getPegOutBalance("0xa554d96413FF72E93437C4072438302C38350EE3").call().then(console.log);



// bridge.methods.getBtcTransactionConfirmations(tx, bh, pmt, mtb).call()
// .then(t => {
// 	console.log('success')
// 	console.log(t)
	
// })
// .catch(e => {
// 	console.log('error')
// 	console.log(e) });

// bridge.methods.registerBtcTransaction("0x02000000031c906a7af99bf059bfad3169e3fdc35949efbc9cfab7acf4222c3d5f972fd469000000006a4730440220484cbb1ad386de74e080d1609981c662b637975329130a335f2a91515bbf347c0220320da0fa9f699ffa79f14d4843d622c55f2881796ba45f97cce8b56362a051060121027e05478598c0798f2059632058284e907b2ae164e9e043549a719e87c6a9da90feffffffdce43e4d6aea558f7dcefa4b51f4a133d7fb71acbf67eb8f3971f6fa500a46480000000048473044022023834902b46e45df06de26d1bf425cd2ac752341ea42ab0bd1a67522c6bc904002205474959a01df092584d5e086b84e76e95bfbe7751d012817b6a40aae9717697c01feffffffa08e305897a37cd974bc4f076d2e88ba5da7f59992fa27fe38e910816078cadc00000000484730440220485a2f214a71218e93812c2f7863c2b9ecc74153a5972054eb73f83a8438444002207adaa10fb3ff176e9e6816c0ef80599be0540a9f8d3d4d68ee6ae9fe64f9e88101feffffff0200e1f5050000000017a91497433ae1859cb691744621cdf4b007cfaebc169d87fa0a8200000000001976a91497474ad4463d16942ed496be29a61adb207a3e1b88ac59050000",
// 1370, "0x41b049db5b9e365bf8b3e0ea595c06af8d5fd5d5b7f8031beae2ebb1f4f8e661"
//   ).send({from: "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826", gas: "900000"}).then(console.log)
// console.log(web3.eth.accounts.decrypt({"address":"9d93929a9099be4355fc2389fbf253982f9df47c","crypto":{"cipher":"aes-128-ctr","ciphertext":"2f6b816b46ea7e9917acad870e4acb8fae1ac57535d20d9f7f5bbd6fc9ceea6f","cipherparams":{"iv":"5d57f07627bfab8e840fea6b7cbeb123"},"kdf":"scrypt","kdfparams":{"dklen":32,"n":262144,"p":1,"r":8,"salt":"5272e0072f0fb5d53171d250729979777abc65f4bd946a995397c26eef33ef92"},"mac":"f7ccbf7492edf922f11d67b5ff864d7d5b5df845586b0669af563626ba1ddad8"},"id":"f344d854-cea8-479c-93ff-0f496e9a4df3","version":3}, "test"))

async function main() {
	// // console.log(Web3.utils.hexToBytes("0x"))
	// const txHeight = await bridge.methods.getBtcTxHashProcessedHeight("4ad9e96e6cb5387d20e0819e28e74cf5ec2eeea59126bc6a3231b1e215bae52e").call();
	// console.log("🚀 ~ file: testRefundPegout.js ~ line 75 ~ main ~ txHeight", txHeight)
	// const response = bestHeight - txHeight + 1;
	// console.log("🚀 ~ file: testRefundPegout.js ~ line 75 ~ main ~ response", response)
	// await web3.eth.sendTransaction({ from: "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826", to: "0x9D93929A9099be4355fC2389FbF253982F9dF47c", value: "9000000" });

	await web3.eth.accounts.wallet.add("0x87ce4239eef3d02cf31223490cd686f6a3d2d338af58646ea36be24c04a926b2");
	const response = await contract.methods.refundPegOut(quotePegOutRegister, tx, bh, pmt, mtb).send({from: "0x9D93929A9099be4355fC2389FbF253982F9dF47c", gas: "6800000"})
	console.log(response);
}

main();