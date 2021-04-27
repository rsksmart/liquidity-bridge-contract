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
        let val = 10;
        let currAddr = web3.eth.currentProvider.getAddress();
        let existing = await instance.getCollateral(currAddr); 

        await instance.register({value : val});

        let current = await instance.getCollateral(currAddr);
        let registered = current.toNumber() - existing.toNumber();

        assert.equal(val, registered);
    });

    it ('should transfer value for user', async () => {
        let val = 10;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 100;
        let userBtcRefundAddress = '0x03';
        let liquidityProviderBtcAddress = '0x04';
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let destAddr = web3.eth.currentProvider.addresses[1];
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x01';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let data = '0x00';
        let callFee = 1;
        let gasLimit = 30000;
        let nonce = 0;
        let peginAmount = val + callFee;
        let lbcAddress = instance.address;        
        let derivationParams = [fedBtcAddress, lbcAddress, liquidityProviderRskAddress, userBtcRefundAddress, rskRefundAddress, liquidityProviderBtcAddress, callFee, destAddr, data, gasLimit, nonce, val];
        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','bytes','address','bytes','uint','address','bytes','uint','uint','uint'],
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

        amount = await instance.registerPegIn.call(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        await instance.registerPegIn(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height
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
        let userBtcRefundAddress = '0x03';
        let liquidityProviderBtcAddress = '0x04';
        let destAddr = mock.address;
        let fedBtcAddress = '0x01';
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
        let derivationParams = [fedBtcAddress, lbcAddress, liquidityProviderRskAddress, userBtcRefundAddress, rskRefundAddress, liquidityProviderBtcAddress, callFee, destAddr, data, gasLimit, nonce, val];
        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','bytes','address','bytes','uint','address','bytes','uint','uint','uint'],
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

        amount = await instance.registerPegIn.call(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        await instance.registerPegIn(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height
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
        let userBtcRefundAddress = '0x03';
        let liquidityProviderBtcAddress = '0x04';
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let destAddr = web3.eth.currentProvider.addresses[1];
        let initialUserBalance = await web3.eth.getBalance(destAddr);
        let fedBtcAddress = '0x01';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let initialLBCBalance = await web3.eth.getBalance(instance.address);
        let initialRefundBalance = await web3.eth.getBalance(rskRefundAddress);
        let data = '0x00';
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let additionalFunds = 1;
        let peginAmount = val + callFee + additionalFunds;
        let lbcAddress = instance.address;
        let derivationParams = [fedBtcAddress, lbcAddress, liquidityProviderRskAddress, userBtcRefundAddress, rskRefundAddress, liquidityProviderBtcAddress, callFee, destAddr, data, gasLimit, nonce, val];
        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','bytes','address','bytes','uint','address','bytes','uint','uint','uint'],
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

        amount = await instance.registerPegIn.call(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        await instance.registerPegIn(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height
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
        let userBtcRefundAddress = '0x03';
        let liquidityProviderBtcAddress = '0x04';
        let destAddr = mock.address;
        let fedBtcAddress = '0x01';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let initialLPBalance = await instance.getBalance(liquidityProviderRskAddress);
        let peginAmount = val + callFee;
        let lbcAddress = instance.address;
        let derivationParams = [fedBtcAddress, lbcAddress, liquidityProviderRskAddress, userBtcRefundAddress, rskRefundAddress, liquidityProviderBtcAddress, callFee, destAddr, data, gasLimit, nonce, val];
        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','bytes','address','bytes','uint','address','bytes','uint','uint','uint'],
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

        await instance.registerPegIn(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);
        finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);

        assert.equal(callFee + val, finalLPBalance.toNumber() - initialLPBalance.toNumber());
        assert.equal(peginAmount - callFee, parseInt(finalUserBalance) - parseInt(initialUserBalance));
    });

    it ('should refund user on missed call', async () => {
        let val = 2;
        let btcRawTransaction = '0x101';
        let partialMerkleTree = '0x202';
        let height = 100;
        let userBtcRefundAddress = '0x03';
        let liquidityProviderBtcAddress = '0x04';
        let destAddr = mock.address;
        let fedBtcAddress = '0x01';
        let liquidityProviderRskAddress = web3.eth.currentProvider.getAddress();
        let rskRefundAddress = web3.eth.currentProvider.addresses[2];
        let callFee = 1;
        let gasLimit = 150000;
        let nonce = 0;
        let data = web3.eth.abi.encodeFunctionCall(mock.abi[2], []);
        let peginAmount = val + callFee;
        let lbcAddress = instance.address;
        let derivationParams = [fedBtcAddress, lbcAddress, liquidityProviderRskAddress, userBtcRefundAddress, rskRefundAddress, liquidityProviderBtcAddress, callFee, destAddr, data, gasLimit, nonce, val];
        let encodedParams = await web3.eth.abi.encodeParameters(
            ['bytes','address','address','bytes','address','bytes','uint','address','bytes','uint','uint','uint'],
            derivationParams
        );
        let preHash = await web3.utils.keccak256(encodedParams);
        let initialUserBalance = await web3.eth.getBalance(rskRefundAddress);

        await bridgeMockInstance.setPegin(preHash, {value : peginAmount});

        await instance.registerPegIn(
            derivationParams,
            btcRawTransaction,
            partialMerkleTree,
            height
        );

        finalUserBalance = await web3.eth.getBalance(rskRefundAddress);

        assert.equal(peginAmount, parseInt(finalUserBalance) - parseInt(initialUserBalance));
    });
});
