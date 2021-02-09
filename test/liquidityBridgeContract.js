const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require('Mock')

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
        let existing = await instance.getDeposit(currAddr); // TODO withdraw instead

        await instance.register({value : val});

        let current = await instance.getDeposit(currAddr);
        let registered = current.toNumber() - existing.toNumber();

        assert.equal(val, registered);
    });

    it ('should transfer value for user', async () => {
        let val = 10;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 100;
        let userBtcRefundAddress = '0x003';
        let liquidityProviderBtcAddress = '0x004';
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let destAddr = web3.eth.currentProvider.addresses[1];
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x01';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let data = '0x00';
        let penaltyFee = 0;
        let successFee = 1;
        let gasLimit = 3;
        let nonce = 0;
        let peginAmount = val + successFee;
        let derivationParams = [fedBtcAddress, liquidityProviderRskAddress, rskRefundAddress, destAddr, data, penaltyFee, successFee, gasLimit, nonce, val];

        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','address','bytes','int','int','int','int','int'],
            derivationParams
        );
        let preHash = await web3.utils.keccak256(encodedParams);        

        await bridgeMockInstance.setPegin(preHash, {value : peginAmount});

        await instance.callForUser(
            derivationParams,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        assert.equal(currentLPBalance.toNumber(), initialLPBalance.toNumber());

        amount = await instance.registerFastBridgeBtcTransaction.call(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress
        );

        await instance.registerFastBridgeBtcTransaction(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress
        );

        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLBCBalance = await web3.eth.getBalance(instance.address);
        finalUserBalance = await web3.eth.getBalance(destAddr);

        assert.equal(peginAmount, amount.toNumber());
        assert.equal(val, parseInt(finalUserBalance) - parseInt(initialUserBalance));
        assert.equal(peginAmount, parseInt(finalLBCBalance) - parseInt(initialLBCBalance));
        assert.equal(peginAmount, finalLPBalance.toNumber() - initialLPBalance.toNumber());
    });

    it ('should call contract for user', async () => {
        let val = 0;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 100;
        let userBtcRefundAddress = '0x003';
        let liquidityProviderBtcAddress = '0x004';
        let destAddr = mock.address;
        let fedBtcAddress = '0x01';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let penaltyFee = 0;
        let successFee = 1;
        let gasLimit = 50000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[0], ['12']);
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let peginAmount = val + successFee;
        let derivationParams = [fedBtcAddress, liquidityProviderRskAddress, rskRefundAddress, destAddr, data, penaltyFee, successFee, gasLimit, nonce, val];
        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','address','bytes','int','int','int','int','int'],
            derivationParams
        );
        let preHash = await web3.utils.keccak256(encodedParams);

        await bridgeMockInstance.setPegin(preHash, {value : peginAmount});
        await mock.set(0);

        await instance.callForUser(
            derivationParams,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);        

        assert.equal(currentLPBalance.toNumber(), initialLPBalance.toNumber());

        amount = await instance.registerFastBridgeBtcTransaction.call(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress
        );

        await instance.registerFastBridgeBtcTransaction(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress
        );

        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLBCBalance = await web3.eth.getBalance(instance.address);

        assert.equal(peginAmount, amount.toNumber());
        assert.equal(peginAmount, finalLPBalance.toNumber() - initialLPBalance.toNumber());
        assert.equal(peginAmount, parseInt(finalLBCBalance) - parseInt(initialLBCBalance));

        finalValue = await mock.check();

        assert.equal(12, finalValue.toNumber());
    });

    it ('should transfer value and refund remaining', async () => {
        let val = 10;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 100;
        let userBtcRefundAddress = '0x003';
        let liquidityProviderBtcAddress = '0x004';
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let destAddr = web3.eth.currentProvider.addresses[1];
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x01';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let initialRefundBalance = await web3.eth.getBalance(rskRefundAddress);
        let data = '0x00';
        let penaltyFee = 0;
        let successFee = 1;
        let gasLimit = 3;
        let nonce = 0;
        let additionalFunds = 1;
        let peginAmount = val + successFee + additionalFunds;
        let derivationParams = [fedBtcAddress, liquidityProviderRskAddress, rskRefundAddress, destAddr, data, penaltyFee, successFee, gasLimit, nonce, val];

        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','address','bytes','int','int','int','int','int'],
            derivationParams
        );
        let preHash = await web3.utils.keccak256(encodedParams);

        await bridgeMockInstance.setPegin(preHash, {value : peginAmount});

        await instance.callForUser(
            derivationParams,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        assert.equal(currentLPBalance.toNumber(), initialLPBalance.toNumber());

        amount = await instance.registerFastBridgeBtcTransaction.call(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress
        );

        await instance.registerFastBridgeBtcTransaction(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress
        );

        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        finalLBCBalance = await web3.eth.getBalance(instance.address);
        finalUserBalance = await web3.eth.getBalance(destAddr);
        finalRefundBalance = await web3.eth.getBalance(rskRefundAddress);

        assert.equal(peginAmount, amount.toNumber());
        assert.equal(val, parseInt(finalUserBalance) - parseInt(initialUserBalance));
        assert.equal(peginAmount - additionalFunds, parseInt(finalLBCBalance) - parseInt(initialLBCBalance));
        assert.equal(peginAmount - additionalFunds, finalLPBalance.toNumber() - initialLPBalance.toNumber());
        assert.equal(additionalFunds, parseInt(finalRefundBalance) - parseInt(initialRefundBalance));
    });

    it ('should refund user on failed call', async () => {
        let val = 2;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 100;
        let userBtcRefundAddress = '0x003';
        let liquidityProviderBtcAddress = '0x004';
        let destAddr = mock.address;
        let fedBtcAddress = '0x01';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let penaltyFee = 1;
        let successFee = 1;
        let gasLimit = 50000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let peginAmount = val + successFee;
        let derivationParams = [fedBtcAddress, liquidityProviderRskAddress, rskRefundAddress, destAddr, data, penaltyFee, successFee, gasLimit, nonce, val];
        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','address','bytes','int','int','int','int','int'],
            derivationParams
        );
        let preHash = await web3.utils.keccak256(encodedParams);
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);

        await bridgeMockInstance.setPegin(preHash, {value : peginAmount});

        await instance.callForUser(
            derivationParams,
            {value : val}
        );

        currentLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        assert.equal(val, parseInt(currentLPBalance) - parseInt(initialLPBalance));

        await instance.registerFastBridgeBtcTransaction(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        assert.equal(successFee + val, finalLPBalance.toNumber() - initialLPBalance.toNumber());
        assert.equal(peginAmount - successFee, parseInt(finalUserBalance) - parseInt(initialUserBalance));
    });

    it ('should refund user on missed call', async () => {
        let val = 2;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 100;
        let userBtcRefundAddress = '0x003';
        let liquidityProviderBtcAddress = '0x004';
        let destAddr = mock.address;
        let fedBtcAddress = '0x01';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let penaltyFee = 1;
        let successFee = 1;
        let gasLimit = 50000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let initialLPDeposit = await instance.getDeposit(liquidityProviderRskAddress);
        let peginAmount = val + successFee;
        let derivationParams = [fedBtcAddress, liquidityProviderRskAddress, rskRefundAddress, destAddr, data, penaltyFee, successFee, gasLimit, nonce, val];
        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','address','bytes','int','int','int','int','int'],
            derivationParams
        );
        let preHash = await web3.utils.keccak256(encodedParams);
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);

        await bridgeMockInstance.setPegin(preHash, {value : peginAmount});

        await instance.registerFastBridgeBtcTransaction(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height,
            userBtcRefundAddress,
            liquidityProviderBtcAddress
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPDeposit = await instance.getDeposit(liquidityProviderRskAddress);

        assert.equal(initialLPDeposit.toNumber() - penaltyFee, finalLPDeposit.toNumber());
        assert.equal(peginAmount + penaltyFee, parseInt(finalUserBalance) - parseInt(initialUserBalance));
    });
});
