
function getTestQuote(lbcAddress, destAddr, callData, liquidityProviderRskAddress, rskRefundAddress, value){
    let val = value || web3.utils.toBN(0);
    let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
    let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
    let fedBtcAddress = '0x0000000000000000000000000000000000000000';
    let callFee = web3.utils.toBN(1);
    let gasLimit = 150000;
    let nonce = 0;
    let data = callData || '0x00';
    let agreementTime = Math.round(Date.now() / 1000);
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
        callOnRegister 
    };

    return quote;
}

async function ensureLiquidityProviderAvailable(instance, liquidityProviderRskAddress, amount) {
    let lpIsAvailable = await instance.isOperational(liquidityProviderRskAddress);
    if(!lpIsAvailable){
        return await instance.register({
            from: liquidityProviderRskAddress,
            value : amount
        });
    }
    return null;
}

function asArray(obj){
    return Object.values(obj);
}

const LP_COLLATERAL = web3.utils.toBN(100);

module.exports = {
    getTestQuote,
    asArray,
    ensureLiquidityProviderAvailable,
    LP_COLLATERAL
  };