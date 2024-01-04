const { expect } = require('chai')

const LiquidityBridgeContract = artifacts.require("LiquidityBridgeContractV2")
const bs58check = require('bs58check')
const pmtBuilder = require("@rsksmart/pmt-builder")

const {
    sleep,
    formatHex,
    sendFromAccount,
    decodeLogs,
    getBitcoinRpcCaller,
    loadConfig,
    sendBtc,
    waitForBtcTransaction
} = require('./common')

describe('Flyover pegout process should', () => {

    let lbc
    let bitcoinRpc

    let quote
    let quoteHash
    let signedQuote

    let lpAccount
    let userAccount
    let interval
    let userBtcEncodedAddress

    let config

    before(async () => {
        config = await loadConfig()
        interval = config.pollingIntervalInSeconds * 1000
        lpAccount = web3.eth.accounts.privateKeyToAccount(config.lpPrivateKey)
        userAccount = web3.eth.accounts.privateKeyToAccount(config.userPrivateKey)

        const lpBtcAddress = bs58check.decode(config.lpBtcAddress)
        const lpAddress = lpAccount.address
        userBtcEncodedAddress = config.userBtcAddress
        const userBtcAddress = bs58check.decode(config.userBtcAddress)
        const userAddress = userAccount.address

        lbc = new web3.eth.Contract(LiquidityBridgeContract.abi, config.lbcAddress)
        bitcoinRpc = getBitcoinRpcCaller(config.btc);

        const timestamp = Math.floor(Date.now() / 1000)
        const transferTime = 1800, expireDate = 3600
        const nonce = Math.floor(Math.random() * Number.MAX_SAFE_INTEGER)
        const height = await web3.eth.getBlock("latest").then(block => block.number);

        const productFeePercentage = await lbc.methods.productFeePercentage().call()
        const value = BigInt(600000000000000000) // 0.6 eth
        const productFee = (BigInt(productFeePercentage) * value) / BigInt(100)
        const daoAddress = await lbc.methods.daoFeeCollectorAddress().call()
        const daoGas = await web3.eth.estimateGas({ to: daoAddress, value: productFee.toString() })
        const gasPrice = await web3.eth.getGasPrice()
        const daoGasCost = gasPrice * daoGas
        const btcNetworkFee = 0.00006700 * 10**18

        quote = {
            lbcAddress: config.lbcAddress,
            lpRskAddress: lpAddress,
            btcRefundAddress: userBtcAddress,
            rskRefundAddress: userAddress,
            lpBtcAddress: lpBtcAddress,
            callFee: BigInt(100000000000000), // fee is 0.0001 eth
            penaltyFee: 1000000,
            nonce: nonce,
            deposityAddress: userBtcAddress,
            value: BigInt(6000000000000000), // 0.006 eth
            agreementTimestamp: timestamp,
            depositDateLimit: timestamp + transferTime,
            depositConfirmations: 1,
            transferConfirmations: 1,
            transferTime: transferTime,
            expireDate: timestamp + expireDate,
            expireBlock: height + 50,
            productFeeAmount: productFee,
            gasFee: daoGasCost + btcNetworkFee
        }

        quoteHash = await lbc.methods.hashPegoutQuote(quote).call()
        signedQuote = lpAccount.sign(quoteHash)
    })

    it('execute depositPegout', async () => {
        const receipt = await sendFromAccount({
            account: userAccount,
            value: quote.callFee + quote.value + quote.productFeeAmount + BigInt(quote.gasFee),
            call: lbc.methods.depositPegout(quote, signedQuote.signature)
        })
        const parsedReceipt = decodeLogs({ abi: LiquidityBridgeContract.abi, receipt })
        expect(parsedReceipt.PegOutDeposit?.quoteHash).eq(quoteHash)
    })

    it('execute refundPegOut', async () => {
        const amountInSatoshi = (quote.value + quote.callFee) / BigInt(10**10)
        const amountInBtc = Number(amountInSatoshi) / 10**8
        if (config.btc.walletPassphrase) {
            await bitcoinRpc('walletpassphrase', {
                passphrase: config.btc.walletPassphrase,
                timeout: 60
            })
        }
        const txHash = await sendBtc({ 
            rpc: bitcoinRpc,
            amountInBtc,
            toAddress: userBtcEncodedAddress,
            data: quoteHash.slice(2)
        })
        const tx = await waitForBtcTransaction({ 
            rpc: bitcoinRpc,
            hash: txHash,
            confirmations: quote.depositConfirmations,
            interval
        })
        const block = await bitcoinRpc("getblock", tx.blockhash)
        const txIndex = block.tx.findIndex(txId => txId === txHash)
        const mb = buildMerkleBranch(block.tx, txHash, txIndex)

        let receipt, waitingForValidations = false
        do {
            try {
                receipt = await sendFromAccount({
                    account: lpAccount,
                    call: lbc.methods.refundPegOut(
                        quoteHash,
                        formatHex(tx.hex),
                        formatHex(tx.blockhash),
                        mb.path,
                        mb.hashes.map(hash => formatHex(hash))
                    ),
                    additionalGasLimit: 5000
                })
                waitingForValidations = false
            } catch (e) {
                waitingForValidations = e.message.includes('LBC049')
                if (!waitingForValidations) {
                    throw e
                }
                console.log('Waiting for bridge validations...')
                await sleep(interval)
            }
        } while (waitingForValidations)
        const parsedReceipt = decodeLogs({ abi: LiquidityBridgeContract.abi, receipt })
        expect(parsedReceipt.PegOutRefunded?.quoteHash).eq(quoteHash)
    })
})

function buildMerkleBranch(transactions, txHash, txIndex) {
    const hashes = []
    const pmt = pmtBuilder.buildPMT(transactions, txHash)

	let path = 0, pathIndex = 0, levelOffset = 0
	let currentNodeOffset = txIndex
    let targetOffset
	for (let levelSize = transactions.length; levelSize > 1; levelSize = Math.floor((levelSize + 1) / 2)) {
		if (currentNodeOffset % 2 == 0) {
			targetOffset = Math.min(currentNodeOffset+1, levelSize-1)
		} else {
			targetOffset = currentNodeOffset - 1
			path = path + (1 << pathIndex)
		}
        hashes.push(pmt.hashes[levelOffset+targetOffset])

		levelOffset += levelSize
		currentNodeOffset = currentNodeOffset / 2
		pathIndex++
	}

    return { hashes, path }
}