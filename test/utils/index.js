const bs58check = require('bs58check')
const { bech32, bech32m } = require("bech32")

function getTestQuote(
  lbcAddress,
  destAddr,
  callData,
  liquidityProviderRskAddress,
  rskRefundAddress,
  value
) {
  let val = value || web3.utils.toBN(0);
  let userBtcRefundAddress = "0x000000000000000000000000000000000000000000";
  let liquidityProviderBtcAddress =
    "0x000000000000000000000000000000000000000000";
  let fedBtcAddress = "0x0000000000000000000000000000000000000000";
  let callFee = web3.utils.toBN(1);
  let gasLimit = 150000;
  let nonce = 0;
  let data = callData || "0x00";
  let agreementTime = Math.floor(Date.now() / 1000);
  let timeForDeposit = 600;
  let callTime = 600;
  let depositConfirmations = 10;
  let penaltyFee = web3.utils.toBN(0);
  let callOnRegister = false;
  let productFeeAmount = web3.utils.toBN(1);
  const gasFee = web3.utils.toBN(1);
  let quote = {
    fedBtcAddress,
    lbcAddress,
    liquidityProviderRskAddress,
    userBtcRefundAddress,
    rskRefundAddress,
    liquidityProviderBtcAddress,
    callFee,
    penaltyFee,
    destAddr,
    data,
    gasLimit,
    nonce,
    val,
    agreementTime,
    timeForDeposit,
    callTime,
    depositConfirmations,
    callOnRegister,
    productFeeAmount,
    gasFee
  };

  return quote;
}

function getTestPegOutQuote(lbcAddress, lpRskAddress, rskRefundAddress, value, btcAddressType = "p2pkh") {
  let depositAddress;
  switch (btcAddressType) {
    case "p2pkh":
      depositAddress = bs58check.decode("mxqk28jvEtvjxRN8k7W9hFEJfWz5VcUgHW")
      break;
    case "p2sh":
      depositAddress = bs58check.decode("2N4DTeBWDF9yaF9TJVGcgcZDM7EQtsGwFjX")
      break;
    case "p2wpkh":
      depositAddress = bech32.decode("tb1qlh84gv84mf7e28lsk3m75sgy7rx2lmvpr77rmw").words
      break;
    case "p2wsh":
      depositAddress = bech32.decode("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7").words
      break;
    case "p2tr":
      depositAddress = bech32m.decode("tb1ptt2hnzgzfhrfdyfz02l02wam6exd0mzuunfdgqg3ttt9yagp6daslx6grp").words
      break;
    default:
      throw new Error("Invalid btcAddressType");
  }

  let valueToTransfer = value || web3.utils.toBN(0);
  let callFee = web3.utils.toBN(1);
  let nonce = 0;
  let agreementTimestamp = 1661788988;
  let expireDate = Math.round(new Date().getTime() / 1000) + 3600;
  let expireBlock = 4000;
  let transferTime = 1661788988;
  let depositDateLimit = Math.round(new Date().getTime() / 1000) + 600;
  let depositConfirmations = 10;
  let transferConfirmations = 10;
  let penaltyFee = web3.utils.toBN(0);
  let productFeeAmount = web3.utils.toBN(1);
  const gasFee = web3.utils.toBN(1);

  let quote = {
    lbcAddress,
    lpRskAddress,
    btcRefundAddress: depositAddress,
    rskRefundAddress,
    lpBtcAddress: "0x000000000000000000000000000000000000000000",
    callFee,
    penaltyFee,
    nonce,
    deposityAddress: depositAddress,
    value: valueToTransfer,
    agreementTimestamp,
    depositDateLimit,
    depositConfirmations,
    transferConfirmations,
    transferTime,
    expireDate,
    expireBlock,
    productFeeAmount,
    gasFee
  };

  return quote;
}

async function ensureLiquidityProviderAvailable(
  instance,
  liquidityProviderRskAddress,
  amount
) {
  let lpIsAvailableForPegin = await instance.isOperational(liquidityProviderRskAddress);
  let lpIsAvailableForPegout = await instance.isOperationalForPegout(liquidityProviderRskAddress);
  if (!lpIsAvailableForPegin || !lpIsAvailableForPegout) {
    return await instance.register(
      "First contract",
      "http://localhost/api",
      true,
      "both",
      {
        from: liquidityProviderRskAddress,
        value: amount,
      }
    );
  }
  return null;
}

function asArray(obj) {
  return Object.values(obj);
}

function timeout(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function reverseHexBytes(hexStr) {
  let arr = [];
  for (let i = 0; i < hexStr.length / 2; i++) {
    let pos = hexStr.length - i * 2;
    arr.push(hexStr.substring(pos - 2, pos));
  }
  return arr.join("");
}

const LP_COLLATERAL = web3.utils.toBN(1500000000000000000);
const ONE_COLLATERAL = web3.utils.toBN(1);
const RESIGN_DELAY_BLOCKS = 60;

async function generateRawTx(lbc, quote, scriptType = "p2pkh") {
  const quoteHash = await lbc.hashPegoutQuote(asArray(quote));
  let outputScript;
  switch (scriptType) {
    case "p2pkh":
      outputScript = [0x76, 0xa9, 0x14, ...quote.deposityAddress.slice(1), 0x88, 0xac]
      break;
    case "p2sh":
      outputScript = [0xa9, 0x14, ...quote.deposityAddress.slice(1), 0x87]
      break;
    case "p2wpkh":
      outputScript = [0x00, 0x14, ...bech32.fromWords(quote.deposityAddress.slice(1))]
      break;
    case "p2wsh":
      outputScript = [0x00, 0x20, ...bech32.fromWords(quote.deposityAddress.slice(1))]
      break;
    case "p2tr":
      outputScript = [0x51, 0x20, ...bech32m.fromWords(quote.deposityAddress.slice(1))]
      break;
    default:
      throw new Error("Invalid scriptType");
  }
  const outputScriptFragment = web3.utils.bytesToHex(outputScript).slice(2);
  const outputSize = (outputScriptFragment.length / 2).toString(16)
  const btcTx = `0x0100000001013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40000000006a47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4ffffffff020100000000000000${outputSize}${outputScriptFragment}0000000000000000226a20${quoteHash.slice(2)}00000000`;
  return btcTx
}

async function mineBlocks (blocks) {
  for (let i = 0; i < blocks; i++) {
    await new Promise((resolve, reject) => {
      web3.currentProvider.send({
          jsonrpc: "2.0",
          method: "evm_mine",
          id: 1
        }, (error, result) => {
          if (error) {
              return reject(error);
          }
          return resolve(result);
        });
    });
  }
};

function parseLiquidityProvider(contractLp) {
  return {
    id: parseInt(contractLp.id),
    provider: contractLp.provider,
    name: contractLp.name,
    apiBaseUrl: contractLp.apiBaseUrl,
    status: contractLp.status,
    providerType: contractLp.providerType,
  };
}

module.exports = {
  getTestQuote,
  getTestPegOutQuote,
  asArray,
  ensureLiquidityProviderAvailable,
  LP_COLLATERAL,
  ONE_COLLATERAL,
  timeout,
  reverseHexBytes,
  generateRawTx,
  mineBlocks,
  RESIGN_DELAY_BLOCKS,
  parseLiquidityProvider
};
