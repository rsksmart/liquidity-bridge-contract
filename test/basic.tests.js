const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require('Mock');
const SignatureValidatorMock = artifacts.require('SignatureValidatorMock');

var chai = require("chai");
const truffleAssertions = require("truffle-assertions");
const utils = require('../test/utils/index');
const BN = web3.utils.BN;
const chaiBN = require('chai-bn')(BN);
chai.use(chaiBN);
const expect = chai.expect;

contract('LiquidityBridgeContract', async accounts => {
    let instance;
    let bridgeMockInstance;
    let signatureValidatorInstance;
    const liquidityProviderRskAddress = accounts[0];

    before(async () => {
        instance = await LiquidityBridgeContract.deployed();
        bridgeMockInstance = await BridgeMock.deployed();
        mock = await Mock.deployed();
        signatureValidatorInstance = await SignatureValidatorMock.deployed();
    });

    beforeEach(async () => {
        await utils.ensureLiquidityProviderAvailable(instance, liquidityProviderRskAddress, utils.LP_COLLATERAL);
    });

    it ('should register liquidity provider', async () => {
        let currAddr = accounts[8];
        let existing = await instance.getCollateral(currAddr); 

        let tx = await instance.register({from: currAddr, value : utils.LP_COLLATERAL});

        let current = await instance.getCollateral(currAddr);
        let registered = current.sub(existing);

        truffleAssertions.eventEmitted(tx, "Register", { 
            from: currAddr
        });
        expect(utils.LP_COLLATERAL).to.be.a.bignumber.eq(registered);
    });

    it ('should fail to register liquidity provider from a contract', async () => {
        let currAddr = accounts[9];

        await truffleAssertions.reverts(mock.callRegister(instance.address, {from : currAddr, value : utils.LP_COLLATERAL}), "Not EOA");
    });

    it('should match lp address with address retrieved from ecrecover', async () => {
        let quote = utils.getTestQuote(
            instance.address, 
            accounts[1],
            '0x00', 
            liquidityProviderRskAddress, 
            accounts[2]);

        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let sig = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        var signer = web3.eth.accounts.recover(quoteHash, sig);

        expect(liquidityProviderRskAddress).to.be.equal(signer);

        await signatureValidatorInstance.verify(liquidityProviderRskAddress, quoteHash, sig);
        let sameSigner = await signatureValidatorInstance.verify.call(liquidityProviderRskAddress, quoteHash, sig);

        if(!sameSigner){
            assert.fail('ecrecover signer does not match with the quoteHash signer.');
        }
	});

    it ('should call contract for user', async () => {
        let rskRefundAddress = accounts[2];
        let destAddr = mock.address;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ['12']);
        let quote = utils.getTestQuote(
            instance.address, 
            destAddr,
            data, 
            liquidityProviderRskAddress, 
            rskRefundAddress,
            web3.utils.toBN(1));

        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let peginAmount = quote.val.add(quote.callFee);
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);

        let firstConfirmationTime = web3.utils.toHex(quote.agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(quote.agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);
        await mock.set(0);

        initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        var cfuTx = await instance.callForUser(
            utils.asArray(quote),
            {value: quote.val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);        

        expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);
            
        amount = await instance.registerPegIn.call(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        await instance.registerPegIn(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLBCBalance = await web3.eth.getBalance(instance.address);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        let lpBal = web3.utils.toBN(finalLPBalance).sub(web3.utils.toBN(initialLPBalance));
        let lbcBal = web3.utils.toBN(finalLBCBalance).sub(web3.utils.toBN(initialLBCBalance));
        expect(peginAmount).to.be.a.bignumber.eq(amount);
        expect(peginAmount).to.be.a.bignumber.eq(lpBal);
        expect(peginAmount).to.be.a.bignumber.eq(lbcBal);
        expect(initialLPDeposit).to.be.a.bignumber.eq(finalLPDeposit);
        truffleAssertions.eventEmitted(cfuTx, "CallForUser", { 
            from: quote.liquidityProviderRskAddress,
            dest: quote.destAddr,
            value: quote.val,
            data: quote.data,
            success: true,
            quoteHash: quoteHash
        });
        finalValue = await mock.check();
        expect(web3.utils.toBN(12)).to.be.a.bignumber.eq(finalValue);
    });

    it ('should fail to call contract for user due to quote amount being below min peg-in', async () => {
        let rskRefundAddress = accounts[2];
        let destAddr = mock.address;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ['12']);
        let quote = utils.getTestQuote(
            instance.address,
            destAddr,
            data,
            liquidityProviderRskAddress,
            rskRefundAddress,
            web3.utils.toBN(0));

        await truffleAssertions.reverts(instance.callForUser(
            utils.asArray(quote),
            {value: quote.val}
        ), "Too low transferred amount");
    });

    it ('should transfer value for user', async () => {
        let rskRefundAddress = accounts[2];
        let destAddr = accounts[1];
        let lbcAddress = instance.address;
        let quote = utils.getTestQuote(
            lbcAddress, 
            destAddr, 
            '0x00', 
            liquidityProviderRskAddress, 
            rskRefundAddress, 
            web3.utils.toBN(10));

        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let peginAmount = quote.val.add(quote.callFee);
        let quoteHash = await instance.hashQuote(utils.asArray(quote));
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(quote.agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(quote.agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);
        initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        let cfuTx = await instance.callForUser(
            utils.asArray(quote),
            {value : quote.val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);

        amount = await instance.registerPegIn.call(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        await instance.registerPegIn(
            utils.asArray(quote),
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLBCBalance = await web3.eth.getBalance(instance.address);
        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        let lbcBal = web3.utils.toBN(finalLBCBalance).sub(web3.utils.toBN(initialLBCBalance));
        let lpBal = web3.utils.toBN(finalLPBalance).sub(web3.utils.toBN(initialLPBalance));
        let usrBal = web3.utils.toBN(finalUserBalance).sub(web3.utils.toBN(initialUserBalance));
        truffleAssertions.eventEmitted(cfuTx, "CallForUser", { 
            from: quote.liquidityProviderRskAddress,
            dest: quote.destAddr,
            value: quote.val,
            data: quote.data,
            success: true,
            quoteHash: quoteHash
        });
        expect(peginAmount).to.be.a.bignumber.eq(amount);
        expect(usrBal).to.be.a.bignumber.eq(quote.val);
        expect(lbcBal).to.be.a.bignumber.eq(peginAmount);
        expect(lpBal).to.be.a.bignumber.eq(peginAmount);
        expect(finalLPDeposit).to.be.a.bignumber.eq(initialLPDeposit);
    });

    it ('should resign', async () => { 
        let lbcAddress = instance.address;
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(lbcAddress);
        let initialLPCol = await instance.getCollateral(liquidityProviderRskAddress);

        let resignTx = await instance.resign();
        let withdrawTx = await instance.withdraw(initialLPBalance);

        let finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let currentLBCBalance = await web3.eth.getBalance(lbcAddress);

        let lbcCurrBal = web3.utils.toBN(initialLBCBalance).sub(web3.utils.toBN(currentLBCBalance))
        expect(initialLPBalance).to.be.a.bignumber.eq(lbcCurrBal);
        expect(finalLPBalance).to.be.a.bignumber.eq(web3.utils.toBN(0));

        let withdrawCollateralTx = await instance.withdrawCollateral();

        let finalLPCol = await instance.getCollateral(liquidityProviderRskAddress);
        let finalLBCBalance = await web3.eth.getBalance(lbcAddress);
        let lbcBal = web3.utils.toBN(currentLBCBalance).sub(web3.utils.toBN(finalLBCBalance));
        truffleAssertions.eventEmitted(resignTx, "Resigned", { 
            from: liquidityProviderRskAddress
        });
        truffleAssertions.eventEmitted(withdrawTx, "Withdrawal", { 
            from: liquidityProviderRskAddress,
            amount: initialLPBalance
        });
        truffleAssertions.eventEmitted(withdrawCollateralTx, "WithdrawCollateral", { 
            from: liquidityProviderRskAddress,
            amount: initialLPCol
        });
        expect(lbcBal).to.be.a.bignumber.eq(initialLPCol);
        expect(web3.utils.toBN(0)).to.be.a.bignumber.eq(finalLPCol);
    });
});
