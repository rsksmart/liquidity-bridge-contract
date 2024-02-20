const { readFile } = require('fs').promises

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
const formatHex = hexString => hexString.startsWith('0x') ? hexString : '0x' + hexString

async function sendFromAccount({ account, value, call, additionalGasLimit }) {
    const gasPrice = await web3.eth.getGasPrice().then(price => {
        return parseInt(price) + parseInt(web3.utils.toWei('1', 'gwei'))
    })
    const tx = {
        from: account.address,
        gasPrice,
        to: call._parent.options.address,
        value: value?.toString(),
        data: call.encodeABI()
    };
    const gasLimit = await call.estimateGas(tx).then(gas => additionalGasLimit? gas + additionalGasLimit : gas)
    tx.gasLimit = gasLimit
    const signedTx = await account.signTransaction(tx)
    return web3.eth.sendSignedTransaction(signedTx.rawTransaction)
}

function decodeLogs({ abi, receipt }) {
  const logs = receipt.logs;
  const parsedReceipt = {}

  for (const log of logs) {
      const event = abi.filter(e => e.type === "event" && e.signature === log.topics[0])[0]
      if (event) {
        const topics = event.anonymous? log.topics : log.topics.slice(1)
        const decodedLog = web3.eth.abi.decodeLog(event.inputs, log.data, topics)
        parsedReceipt[event.name] = decodedLog
      }
  }
  return parsedReceipt
}

function getBitcoinRpcCaller({ url, user, pass }, debug = false) {
    const headers = new Headers();
    headers.append("content-type", "application/json");
    const token = Buffer.from(`${user}:${pass}`).toString('base64')
    headers.append("Authorization", "Basic "+token);

    return async function (method, ...args) {
        const body = JSON.stringify({ 
            jsonrpc: "1.0",
            method: method.toLowerCase(),
            params: typeof args[0] === 'object' ? args[0] : args
        })
        const requestOptions = { method: 'POST', headers, body }
        if (debug) {
            console.log(body)
        }
        return fetch(url, requestOptions)
            .then(response => response.json())
            .then(response => {
                if (response.error) {
                    throw response.error
                }
                return response.result
            })
    }
}

async function loadConfig() {
    const buffer = await readFile('integration-test/test.config.json')
    return JSON.parse(buffer.toString())
}
async function sendBtc({ toAddress, amountInBtc, rpc, data }) {
    const outputs = [ { [toAddress]: amountInBtc.toString() } ]
    const fundOptions = { fee_rate: 25 }
    if (data) {
        outputs.push({ data })
        fundOptions.changePosition = 2
    }
    const rawSendTx = await rpc("createrawtransaction", {
        inputs: [],
        outputs
    })
    const fundedSendTx = await rpc("fundrawtransaction", rawSendTx, fundOptions)
    const signedSendTx = await rpc("signrawtransactionwithwallet", fundedSendTx.hex)
    return rpc("sendrawtransaction", signedSendTx.hex)
}

async function waitForBtcTransaction({ rpc, hash, confirmations, interval }) {
    let tx
    while (!tx?.confirmations || confirmations > tx.confirmations) {
        tx = await rpc("gettransaction", hash)
        if (confirmations > tx.confirmations) {
            console.log(`Waiting for transaction ${hash} (${tx.confirmations} confirmations)`)
            await sleep(interval)
        }
    }
    console.log("Transaction confirmed")
    return tx
}

module.exports = {
    sleep,
    formatHex,
    sendFromAccount,
    decodeLogs,
    getBitcoinRpcCaller,
    loadConfig,
    sendBtc,
    waitForBtcTransaction
}