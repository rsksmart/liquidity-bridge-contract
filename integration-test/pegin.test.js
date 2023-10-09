const { expect } = require('chai')

const LiquidityBridgeContract = artifacts.require("LiquidityBridgeContract")
const BtcUtils = artifacts.require("BtcUtils")
const bs58check = require('bs58check')
const bs58 = require('bs58')
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

describe('Flyover pegin process should', () => {
    let lbc
    let btcUtils
    let bitcoinRpc

    let quote
    let quoteHash
    let signedQuote

    let lpAccount
    let interval

    before(async () => {
        const config = await loadConfig()
        interval = config.pollingIntervalInSeconds * 1000
        lpAccount = web3.eth.accounts.privateKeyToAccount(config.lpPrivateKey)
        const userAccount = web3.eth.accounts.privateKeyToAccount(config.userPrivateKey)

        const lpBtcAddress = bs58check.decode(config.lpBtcAddress)
        const lpAddress = lpAccount.address
        const userBtcAddress = bs58check.decode(config.userBtcAddress)
        const userAddress = userAccount.address

        lbc = new web3.eth.Contract(LiquidityBridgeContract.abi, config.lbcAddress)
        btcUtils = new web3.eth.Contract(BtcUtils.abi, config.btcUtilsAddress)
        bitcoinRpc = getBitcoinRpcCaller(config.btc);

        const timestamp = Math.floor(Date.now() / 1000)
        const transferTime = 1800
        const gasLimit = await web3.eth.estimateGas({ to: userAddress, data: '0x' })
        const gasCost = await web3.eth.getGasPrice().then(price => price * gasLimit)
        const fedAddress = await web3.eth.call({
                to: '0x0000000000000000000000000000000001000006',
                data: web3.eth.abi.encodeFunctionSignature('getFederationAddress()')
            })
            .then(fed => {
                const decodeResult = web3.eth.abi.decodeParameters(['string'], fed)
                return bs58check.decode(decodeResult[0]).slice(1)
            })
        const nonce = Math.floor(Math.random() * Number.MAX_SAFE_INTEGER)

        quote = {
            fedBtcAddress: fedAddress,
            lbcAddress: config.lbcAddress,
            liquidityProviderRskAddress: lpAddress,
            btcRefundAddress: userBtcAddress,
            rskRefundAddress: userAddress,
            liquidityProviderBtcAddress: lpBtcAddress,
            callFee: BigInt(100000000000000 + gasCost), // fee is 0.0001 eth
            penaltyFee: 1000000,
            contractAddress: userAddress,
            data: '0x',
            gasLimit: gasLimit,
            nonce: nonce,
            value: BigInt(6000000000000000), // 0.006 eth
            agreementTimestamp: timestamp,
            timeForDeposit: transferTime,
            callTime: transferTime * 2,
            depositConfirmations: 1,
            callOnRegister: false
        }


        quoteHash = await lbc.methods.hashQuote(quote).call()
        signedQuote = lpAccount.sign(quoteHash)
    })

    it('execute callForUser', async () => {
        const cfuExtraGas = 180000
        const receipt = await sendFromAccount({
            account: lpAccount,
            value: quote.callFee + quote.value,
            call: lbc.methods.callForUser(quote),
            additionalGasLimit: quote.gasLimit + cfuExtraGas
        })
        const parsedReceipt = decodeLogs({ abi: LiquidityBridgeContract.abi, receipt })
        expect(parsedReceipt.CallForUser?.success).to.be.true
    })
    
    it('execute registerPegIn', async () => {
        const derivationAddress = await getDervivationAddress({ quote, quoteHash, btcUtilsInstance: btcUtils, lbc})

        const amountInSatoshi = (quote.value + quote.callFee) / BigInt(10**10)
        const amountInBtc = Number(amountInSatoshi) / 10**8

        const txHash = await sendBtc({ rpc: bitcoinRpc, amountInBtc, toAddress: derivationAddress })
        const tx = await waitForBtcTransaction({ rpc: bitcoinRpc, hash: txHash, confirmations: quote.depositConfirmations, interval })

        const block = await bitcoinRpc("getblock", tx.blockhash)
        const rawTx = await bitcoinRpc("getrawtransaction", txHash)
        const pmt = pmtBuilder.buildPMT(block.tx, txHash)
        let receipt, waitingForValidations = false
        do {
            try {
                receipt = await sendFromAccount({
                    account: lpAccount,
                    call: lbc.methods.registerPegIn(
                        quote,
                        signedQuote.signature,
                        formatHex(rawTx),
                        formatHex(pmt.hex),
                        block.height
                    )
                })
                waitingForValidations = false
            } catch (e) {
                waitingForValidations = e.message.includes('LBC031')
                if (!waitingForValidations) {
                    throw e
                }
                console.log('Waiting for bridge validations...')
                await sleep(interval)
            }
        } while (waitingForValidations)

        expect(Boolean(receipt.status)).to.be.true
    }) 
})

async function getDervivationAddress({ quote, quoteHash, btcUtilsInstance }) {
    const derivationAddress = web3.utils.soliditySha3(
        { type: 'bytes32', value: formatHex(quoteHash) },
        { type: 'bytes', value: web3.utils.bytesToHex(quote.btcRefundAddress) },
        { type: 'address', value: quote.lbcAddress },
        { type: 'bytes', value: web3.utils.bytesToHex(quote.liquidityProviderBtcAddress) }
    );
    let redeemScript = web3.utils.hexToBytes(derivationAddress)
    redeemScript.unshift(32) // 0x20
    redeemScript.push(117) // 0x75
    const powpegRedeemScript = await web3.eth.call({
            to: '0x0000000000000000000000000000000001000006',
            data: web3.eth.abi.encodeFunctionSignature('getActivePowpegRedeemScript()')
        }).then(script => {
            const result = web3.eth.abi.decodeParameters(['bytes'], script)[0]
            return web3.utils.hexToBytes(result)
        })
    redeemScript = redeemScript.concat(powpegRedeemScript)

    const derivationAddressBytes = await btcUtilsInstance.methods.getP2SHAddressFromScript(
        web3.utils.bytesToHex(redeemScript), 
        false
    ).call()
    return bs58.encode(web3.utils.hexToBytes(derivationAddressBytes))
}