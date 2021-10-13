const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require('Mock')
const truffleAssert = require('truffle-assertions');

contract('LiquidityBridgeContract', async accounts => {
    let instance;
    let bridgeMockInstance;
    
    beforeEach(async () => {
        instance = await LiquidityBridgeContract.deployed();
        bridgeMockInstance = await BridgeMock.deployed();
        mock = await Mock.deployed()
    });

    it ('should register liquidity provider', async () => {
        let val = 100;
        let currAddr = web3.eth.currentProvider.getAddress();
        let existing = await instance.getCollateral(currAddr); 

        await instance.register({value : val});

        let current = await instance.getCollateral(currAddr);
        let registered = current.toNumber() - existing.toNumber();

        assert.equal(val, registered);
    });

    it ('should not allow attacker to steal funds', async () => {
        // The attacker controls a liquidity provider and also a destination address
        // Note that these could be the same address, separated for clarity
        let attackingLP = web3.eth.currentProvider.addresses[7];
        let attackerCollateral = web3.utils.toWei("10");
        await instance.register.call({
                value: attackerCollateral, 
                from: attackingLP
            });


        let goodLP = web3.eth.currentProvider.addresses[8];
        let goodProviderCollateral = web3.utils.toWei("30");
        await instance.register.call({
            value: goodProviderCollateral, 
            from: goodLP
        });

        let attackerDestAddress = web3.eth.currentProvider.addresses[9];
        // Let's record how much money is there in the LBC and how much
        // is in control of the attacker
        let initialAttackerBalance = await web3.eth.getBalance(attackerDestAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);

        // Add funds from an innocent liquidity provider, note again this could be
        // done by an attacker
        // The quote value in wei should be bigger than 2**63-1. 10 RBTC is a good approximation.
        let quoteValue = web3.utils.numberToHex(web3.utils.toWei("10"));
        // Let's create the evil quote.
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let rskRefundAddress = attackerDestAddress;
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = attackingLP;
        let data = '0x00';
        let callFee = 1;        
        let gasLimit = 30000;
        let nonce = 1;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 0;
        let callOnRegister = true;
        let quote = [
            fedBtcAddress,
            lbcAddress,
            liquidityProviderRskAddress,
            userBtcRefundAddress,
            rskRefundAddress,
            liquidityProviderBtcAddress,
            callFee,
            penaltyFee,
            attackerDestAddress,
            data,
            gasLimit,
            nonce,
            quoteValue,
            agreementTime,
            timeForDeposit,
            callTime,
            depositConfirmations,
            callOnRegister
        ];
        // Let's now register our quote in the bridge... note that the
        // value is only a hundred wei
        let transferedInBTC = 100;
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);
        await bridgeMockInstance.setPegin(quoteHash, {value : transferedInBTC});
        // Register the peg in with the evil quote
        amount = await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );
        // The user will _not_ get their money back, as their deposit
        // of only 100 wei was not enough to cover the quoteValue of more 20 wei
        // They don't even get their 100 back, as it is not enough to surpass dust.
        let finalAttackerBalance = await web3.eth.getBalance(attackerDestAddress);
        let lbcFinalBalance = await web3.eth.getBalance(lbcAddress);

        assert.equal(initialAttackerBalance, finalAttackerBalance);
        assert.notEqual(lbcFinalBalance, 0)                
    });

    it ('should transfer value for user', async () => {
        let val = 10;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let destAddr = web3.eth.currentProvider.addresses[1];
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let data = '0x00';
        let callFee = 1;
        let gasLimit = 30000;
        let nonce = 0;
        let peginAmount = val + callFee;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 0;
        let callOnRegister = false;
        let quote = [
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
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);
        initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await instance.callForUser(
            quote,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        assert.equal(currentLPBalance.toNumber(), initialLPBalance.toNumber());

        amount = await instance.registerPegIn.call(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLBCBalance = await web3.eth.getBalance(instance.address);
        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        assert.equal(peginAmount, amount.toNumber());
        assert.equal(val, parseInt(finalUserBalance) - parseInt(initialUserBalance));
        assert.equal(peginAmount, parseInt(finalLBCBalance) - parseInt(initialLBCBalance));
        assert.equal(peginAmount, finalLPBalance.toNumber() - initialLPBalance.toNumber());
        assert.equal(initialLPDeposit.toNumber(), finalLPDeposit.toNumber());
    });
    
    it ('should call contract for user', async () => {
        let val = 0;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let destAddr = mock.address;
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let callFee = 1;
        let gasLimit = 30000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ['12']);
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let peginAmount = val + callFee;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 0;
        let callOnRegister = false;
        let quote = [
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
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);
        await mock.set(0);

        initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await instance.callForUser(
            quote,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);        

        assert.equal(currentLPBalance.toNumber(), initialLPBalance.toNumber());
            
        amount = await instance.registerPegIn.call(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLBCBalance = await web3.eth.getBalance(instance.address);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        assert.equal(peginAmount, amount.toNumber());
        assert.equal(peginAmount, finalLPBalance.toNumber() - initialLPBalance.toNumber());
        assert.equal(peginAmount, parseInt(finalLBCBalance) - parseInt(initialLBCBalance));
        assert.equal(initialLPDeposit.toNumber(), finalLPDeposit.toNumber());

        finalValue = await mock.check();

        assert.equal(12, finalValue.toNumber());
    });

    it ('should transfer value and refund remaining', async () => {
        let val = 10;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let destAddr = web3.eth.currentProvider.addresses[1];
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let initialRefundBalance = await web3.eth.getBalance(rskRefundAddress);
        let data = '0x00';
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let additionalFunds = 1000000000000;
        let peginAmount = val + callFee + additionalFunds;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 0;
        let callOnRegister = false;
        let quote = [
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
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await instance.callForUser(
            quote,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        assert.equal(currentLPBalance.toNumber(), initialLPBalance.toNumber());

        amount = await instance.registerPegIn.call(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLBCBalance = await web3.eth.getBalance(instance.address);
        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalRefundBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        assert.equal(peginAmount, amount.toNumber());
        assert.equal(val, parseInt(finalUserBalance) - parseInt(initialUserBalance));
        assert.equal(peginAmount - additionalFunds, parseInt(finalLBCBalance) - parseInt(initialLBCBalance));
        assert.equal(peginAmount - additionalFunds, finalLPBalance.toNumber() - initialLPBalance.toNumber());
        assert.equal(additionalFunds, parseInt(finalRefundBalance) - parseInt(initialRefundBalance));
        assert.equal(initialLPDeposit.toNumber(), finalLPDeposit.toNumber());
    });

    it ('should pay with insufficient deposit', async () => {
        let val = 10;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let destAddr = web3.eth.currentProvider.addresses[1];
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let data = '0x00';
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let additionalFunds = -1;
        let peginAmount = val + callFee + additionalFunds;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 0;
        let callOnRegister = false;
        let quote = [
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
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await instance.callForUser(
            quote,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        assert.equal(currentLPBalance.toNumber(), initialLPBalance.toNumber());

        amount = await instance.registerPegIn.call(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLBCBalance = await web3.eth.getBalance(instance.address);
        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        assert.equal(peginAmount, amount.toNumber());
        assert.equal(val, parseInt(finalUserBalance) - parseInt(initialUserBalance));
        assert.equal(peginAmount, parseInt(finalLBCBalance) - parseInt(initialLBCBalance));
        assert.equal(peginAmount, finalLPBalance.toNumber() - initialLPBalance.toNumber());
        assert.equal(initialLPDeposit.toNumber(), finalLPDeposit.toNumber());
    });

    it ('should perform call on registerPegIn', async () => {
        let val = 10;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let destAddr = web3.eth.currentProvider.addresses[1];
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let initialRefundBalance = await web3.eth.getBalance(rskRefundAddress);
        let data = '0x00';
        let callFee = 1000000000000;
        let gasLimit = 30000;
        let nonce = 0;
        let peginAmount = val + callFee;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 0;
        let callOnRegister = true;
        let quote = [
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
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);
        initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        amount = await instance.registerPegIn.call(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLBCBalance = await web3.eth.getBalance(instance.address);
        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        finalRefundBalance = await web3.eth.getBalance(rskRefundAddress);

        assert.equal(peginAmount, amount.toNumber());
        assert.equal(val, parseInt(finalUserBalance) - parseInt(initialUserBalance));
        assert.equal(callFee, parseInt(finalRefundBalance) - parseInt(initialRefundBalance));
        assert.equal(parseInt(finalLBCBalance), parseInt(initialLBCBalance));
        assert.equal(finalLPBalance.toNumber(), initialLPBalance.toNumber());
        assert.equal(penaltyFee, initialLPDeposit.toNumber() - finalLPDeposit.toNumber());
    });

    it ('should refund user on failed call', async () => {
        let val = 1000000000000;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let destAddr = mock.address;
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let peginAmount = val + callFee;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 0;
        let callOnRegister = false;
        let quote = [
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
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';

        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await instance.callForUser(
            quote,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        assert.equal(val, parseInt(currentLPBalance) - parseInt(initialLPBalance));

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        assert.equal(callFee + val, finalLPBalance.toNumber() - initialLPBalance.toNumber());
        assert.equal(peginAmount - callFee, parseInt(finalUserBalance) - parseInt(initialUserBalance));
        assert.equal(initialLPDeposit.toNumber(), finalLPDeposit.toNumber());
    });

    it ('should refund user on missed call', async () => {
        let val = 1000000000000;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let destAddr = mock.address;
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let peginAmount = val + callFee;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 10;
        let callOnRegister = false;
        let quote = [
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
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialAltBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let reward = Math.floor(penaltyFee / 10);
        let initialLbcBalance = await web3.eth.getBalance(instance.address);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalAltBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        finalLbcBalance = await web3.eth.getBalance(instance.address);

        assert.equal(peginAmount, parseInt(finalUserBalance) - parseInt(initialUserBalance));
        assert.equal(reward, finalAltBalance.toNumber() - initialAltBalance.toNumber());
        assert.equal(penaltyFee, initialLPDeposit.toNumber() - finalLPDeposit.toNumber());
        assert.equal(parseInt(initialLbcBalance), parseInt(finalLbcBalance));
    });

    it ('should not penalize with late deposit', async () => {
        let val = 1000000000000;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let destAddr = mock.address;
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let peginAmount = val + callFee;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 1;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 10;
        let callOnRegister = false;
        let quote = [
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
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        assert.equal(peginAmount, parseInt(finalUserBalance) - parseInt(initialUserBalance));
        assert.equal(initialLPDeposit.toNumber(), finalLPDeposit.toNumber());
    });

    it ('should not penalize with insufficient deposit', async () => {
        let val = 1000000000000;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let destAddr = mock.address;
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let peginAmount = val + callFee - 1;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 600;
        let depositConfirmations = 10;
        let penaltyFee = 10;
        let callOnRegister = false;
        let quote = [
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
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 600).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        assert.equal(peginAmount, parseInt(finalUserBalance) - parseInt(initialUserBalance));
        assert.equal(initialLPDeposit.toNumber(), finalLPDeposit.toNumber());
    });

    it ('should penalize on late call', async () => {
        let val = 10;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let destAddr = web3.eth.currentProvider.addresses[1];
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let data = '0x00';
        let callFee = 1;
        let gasLimit = 30000;
        let nonce = 0;
        let peginAmount = val + callFee;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 1;
        let depositConfirmations = 10;
        let penaltyFee = 10;
        let callOnRegister = false;
        let quote = [
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
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 1).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let reward = Math.floor(penaltyFee / 10);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        await instance.callForUser(
            quote,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        assert.equal(currentLPBalance.toNumber(), initialLPBalance.toNumber());

        await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);

        assert.equal(val, parseInt(finalUserBalance) - parseInt(initialUserBalance));
        assert.equal(penaltyFee, initialLPDeposit.toNumber() - finalLPDeposit.toNumber());
        assert.equal(reward +  peginAmount, finalLPBalance.toNumber() - initialLPBalance.toNumber());        
    });

    it ('should not undeflow when penalty is higher than collateral', async () => {
        let val = 10;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 10;
        let userBtcRefundAddress = '0x000000000000000000000000000000000000000000';
        let liquidityProviderBtcAddress = '0x000000000000000000000000000000000000000000';
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let destAddr = web3.eth.currentProvider.addresses[1];
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x0000000000000000000000000000000000000000';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let data = '0x00';
        let callFee = 1;
        let gasLimit = 300000;
        let nonce = 0;
        let peginAmount = val + callFee;
        let lbcAddress = instance.address;
        let agreementTime = Math.round(Date.now() / 1000);
        let timeForDeposit = 600;
        let callTime = 1;
        let depositConfirmations = 10;
        let penaltyFee = 11;
        let callOnRegister = false;
        let quote = [
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
        ];
        let quoteHash = await instance.hashQuote(quote);
        let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
        let firstConfirmationTime = web3.utils.toHex(agreementTime + 300).slice(2, 12);
        let nConfirmationTime = web3.utils.toHex(agreementTime + 1).slice(2, 12);
        let firstHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + firstConfirmationTime + '0000000000000000';
        let nHeader = '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' + nConfirmationTime + '0000000000000000';
        let initialLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        let reward = Math.floor(penaltyFee / 10);

        await bridgeMockInstance.setPegin(quoteHash, {value : peginAmount});
        await bridgeMockInstance.setHeader(height, firstHeader);
        await bridgeMockInstance.setHeader(height + depositConfirmations - 1, nHeader);

        await instance.callForUser(
            quote,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        assert.equal(currentLPBalance.toNumber(), initialLPBalance.toNumber());

        let tx = await instance.registerPegIn(
            quote,
            signature,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLPDeposit = await instance.getCollateral(liquidityProviderRskAddress);
        
        truffleAssert.eventEmitted(tx, "Penalized");
        assert.equal(0, finalLPDeposit.toNumber());
        assert.equal(reward +  peginAmount, finalLPBalance.toNumber() - initialLPBalance.toNumber());        
    });

    it ('should resign', async () => {
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let lbcAddress = instance.address;
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(lbcAddress);
        let initialLPCol = await instance.getCollateral(liquidityProviderRskAddress);

        await instance.resign();
        await instance.withdraw(initialLPBalance);

        let finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let currentLBCBalance = await web3.eth.getBalance(lbcAddress);

        assert.equal(initialLPBalance.toNumber(), parseInt(initialLBCBalance) - parseInt(currentLBCBalance));
        assert.equal(0, finalLPBalance.toNumber());

        await instance.withdrawCollateral();

        let finalLPCol = await instance.getCollateral(liquidityProviderRskAddress);
        let finalLBCBalance = await web3.eth.getBalance(lbcAddress);

        assert.equal(initialLPCol.toNumber(), parseInt(currentLBCBalance) - parseInt(finalLBCBalance));
        assert.equal(0, finalLPCol.toNumber());
    });
});
