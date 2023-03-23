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
  let agreementTime = 1661788988;
  let timeForDeposit = 600;
  let callTime = 600;
  let depositConfirmations = 10;
  let penaltyFee = web3.utils.toBN(0);
  let callOnRegister = false;
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
  };

  return quote;
}

function getTestPegOutQuote(
  lbcAddress,
  lpRskAddress,
  rskRefundAddress,
  value
) {
  let valueToTransfer = value || web3.utils.toBN(0);
  let callFee = web3.utils.toBN(1);
  let nonce = 0;
  let agreementTimestamp = 1661788988;
  let expireDate = Math.round(new Date().getTime() / 1000) + 3600;
  let expireBlock = 4000;
  let transferTime = 1661788988;
  let depositDateLimit = 600;
  let depositConfirmations = 10;
  let transferConfirmations = 10;
  let penaltyFee = web3.utils.toBN(0);

  let quote = {
    lbcAddress,
    lpRskAddress,
    btcRefundAddress: "0x000000000000000000000000000000000000000000",
    rskRefundAddress,
    lpBtcAddress: "0x000000000000000000000000000000000000000000",
    callFee,
    penaltyFee,
    nonce,
    deposityAddress: "0x000000000000000000000000000000000000000000",
    gasLimit: 21000,
    value: valueToTransfer,
    agreementTimestamp,
    depositDateLimit,
    depositConfirmations,
    transferConfirmations,
    transferTime,
    expireDate,
    expireBlock,
  };

  return quote;
}

async function ensureLiquidityProviderAvailable(
  instance,
  liquidityProviderRskAddress,
  amount
) {
  let lpIsAvailable = await instance.isOperational(liquidityProviderRskAddress);
  if (!lpIsAvailable) {
    return await instance.register(
      "First contract",
      10,
      7200,
      3600,
      10,
      100,
      "http://localhost/api",
      true,
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

const LP_COLLATERAL = web3.utils.toBN(100);
const ONE_COLLATERAL = web3.utils.toBN(1);

module.exports = {
  getTestQuote,
  getTestPegOutQuote,
  asArray,
  ensureLiquidityProviderAvailable,
  LP_COLLATERAL,
  ONE_COLLATERAL,
  timeout,
  reverseHexBytes,
};
