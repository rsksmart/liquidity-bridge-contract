const LiquidityBridgeContractV2 = artifacts.require("LiquidityBridgeContractV2.sol");
const BridgeMock = artifacts.require("BridgeMock");
const Mock = artifacts.require("Mock");
const SignatureValidatorMock = artifacts.require("SignatureValidatorMock");
const BtcUtils = artifacts.require("BtcUtils");

var chai = require("chai");
const truffleAssertions = require("truffle-assertions");
const utils = require("../test/utils/index");
const BN = web3.utils.BN;
const chaiBN = require("chai-bn")(BN);
chai.use(chaiBN);
const expect = chai.expect;
const bs58check = require('bs58check')
const bs58 = require('bs58');

contract("LiquidityBridgeContractV2.sol", async (accounts) => {
  let instance;
  let bridgeMockInstance;
  let mock;
  let signatureValidatorInstance;
  let btcUtils;
  const liquidityProviderRskAddress = accounts[0];
  var providerList = [];
  before(async () => {
    const proxy = await LiquidityBridgeContractV2.deployed();
    instance = await LiquidityBridgeContractV2.at(proxy.address);
    bridgeMockInstance = await BridgeMock.deployed();
    mock = await Mock.deployed();
    signatureValidatorInstance = await SignatureValidatorMock.deployed();
    btcUtils = await BtcUtils.deployed();
  });

  beforeEach(async () => {
    await utils.ensureLiquidityProviderAvailable(
      instance,
      liquidityProviderRskAddress,
      utils.LP_COLLATERAL
    );
  });

  it('should refund pegin with wrong amount without penalizing the LP (real cases)', async () => {
    const cases = [
      {
        quote: {
          fedBtcAddress: bs58check.decode("3LxPz39femVBL278mTiBvgzBNMVFqXssoH").slice(1),
          lbcAddress: '0xAA9cAf1e3967600578727F975F283446A3Da6612',
          liquidityProviderRskAddress: '0x4202bac9919c3412fc7c8be4e678e26279386603',
          btcRefundAddress: bs58check.decode("1K5X7aTGfZGksihgNdDschakaxp8ZhT1F3"),
          rskRefundAddress: '0x1bf357F3CcCe62a5Dd1035c79070BdA219C53B10',
          liquidityProviderBtcAddress: bs58check.decode("17kksixYkbHeLy9okV16kr4eAxVhFkRhP"),
          callFee: web3.utils.toBN('100000000000000'),
          penaltyFee: web3.utils.toBN('10000000000000'),
          contractAddress: '0x1bf357F3CcCe62a5Dd1035c79070BdA219C53B10',
          data:'0x',
          gasLimit: 21000,
          nonce: '907664817259568253',
          value: web3.utils.toBN('5200000000000000'),
          agreementTimestamp: 1727278204,
          timeForDeposit: 3600,
          callTime: 7200,
          depositConfirmations: 2,
          callOnRegister: false,
          productFeeAmount: 0,
          gasFee: web3.utils.toBN('1354759560000'),
        },
        quoteHash: 'b21ead431a1c3efd1759b62a56c253d740d1bf3c3673cd060aed64906a82c1c3',
        signature: 'c72e3e5bb9cf6bf3db568df18d2dba80896490cda7371c4643cad116d54d46c50a368d4cfa0b963468c5db15b773f4d1ea1ab69565a3f903ac3ab363204ba3bc1c',
        btcRawTx: '020000000212bebc8ba671aa9af2e3984af89366b5594ed115dbbaef64a41e8650cd4a53ea0000000017160014fe7b123124c87300e8ba30f0e2eafdd8e1f2b337ffffffff046d8f4e5fa8d6cc5fa23c50640249461b646e8a4722c9cfbfbff00c049d559f0000000017160014fe7b123124c87300e8ba30f0e2eafdd8e1f2b337ffffffff02d71608000000000017a9149fa51efd2954990e4974e7b13468fb8be54512d8872d2507000000000017a914b979999438ade0fdd2cf303fca55ea29aec2392b8700000000',
        pmt: '800c00000d3eb13be27a4110f06ca8e4b4b00103e10ac6ba5f9123934764ac9555e2ec3c7b88a5464adca8b40a548741a8262dc2ab228f89cbd51bbf57f3f5d67130820ae3f9b7625821c2d9718d6611de40edfa1eb42181f180aab3891730584921a125dddba628c1d3f5fca59e0b68494aae191ab14db30b79e07962da298a52bcf077905661f80bd5731e0c80524ba2f7dcad0bd05a0d470bccdb5c5889c9c71ac7c5bca7f6cebd492154af69f2b98bcf7995444c765a18445a5ef212eb5f8ead5a441a45536e4075022614df043d03b2449113a00f32cff333024d3a1d66d84d4a31c012bebc8ba671aa9af2e3984af89366b5594ed115dbbaef64a41e8650cd4a53ea34b89cb98fac941bdd048d4a8f371d7b9f132ad19f1542556c89b4e8701022de51f6d49aa8f7e7d01591de9bdef65351e8590f111ea9be5550f66a3d4a734758e26b8edf2bfe9c4375929fea7b7197a24589648f8e7b934a6caa2d9c7583e64a28db12de953b0abddbdc3edb28b845eaca02f56dd52aa04e3131dc539c0f646f35751d1ec529231acd5cb079b4a2b678ecd3fc07636be878e6336d546518562e04af6a1500',
        height: 862825,
        refundAmount: '5301350000000000'
      },
      {
        quote: {
          fedBtcAddress: bs58check.decode("3LxPz39femVBL278mTiBvgzBNMVFqXssoH").slice(1),
          lbcAddress: '0xAA9cAf1e3967600578727F975F283446A3Da6612',
          liquidityProviderRskAddress: '0x4202bac9919c3412fc7c8be4e678e26279386603',
          btcRefundAddress: bs58check.decode("171gGjg8NeLUonNSrFmgwkgT1jgqzXR6QX"),
          rskRefundAddress: '0xaD0DE1962ab903E06C725A1b343b7E8950a0Ff82',
          liquidityProviderBtcAddress: bs58check.decode("17kksixYkbHeLy9okV16kr4eAxVhFkRhP"),
          callFee: web3.utils.toBN('100000000000000'),
          penaltyFee: web3.utils.toBN('10000000000000'),
          contractAddress: '0xaD0DE1962ab903E06C725A1b343b7E8950a0Ff82',
          data:'0x',
          gasLimit: 21000,
          nonce: '8373381263192041574',
          value: web3.utils.toBN('8000000000000000'),
          agreementTimestamp: 1727298699,
          timeForDeposit: 3600,
          callTime: 7200,
          depositConfirmations: 2,
          callOnRegister: false,
          productFeeAmount: 0,
          gasFee: web3.utils.toBN('1341211956000'),
        },
        quoteHash: '9ef0d0c376a0611ee83a1d938f88cdc8694d9cb6e35780d253fb945e92647d68',
        signature: '8ccd018b5c1fb7eceba2a13f8c977ae362c0daccafa6d77a5eb740527dd177620bb6c2d072d68869b3a08b193b1356de564e73233ea1c2686078bf87e3c909a31c',
        btcRawTx: '010000000148e9e71dafee5a901be4eceb5aca361c083481b70496f4e3da71e5d969add1820000000017160014b88ef07cd7bcc022b6d73c4764ce5db0887d5b05ffffffff02965c0c000000000017a9141b67149e474f0d7757181f4db89257f27a64738387125b01000000000017a914785c3e807e54dc41251d6377da0673123fa87bc88700000000',
        pmt: 'a71100000e7fe369f81a807a962c8e528debd0b46cbfa4f8dfbc02a62674dd41a73f4c4bde0508a9e309e5836703375a58ab116b95434552ca2e460c3273cd2caa13350aefc3c8152a8150f738cd18ff33e69f19b727bff9c2b92aa06e6d0971e9b49893075f2d926bbb9f0884640363b79b6a668a178f140c13f25b48ec975357822ce38c733f6de9b32f6910ff3cd838efd274cd784ab204b74f281ef68146c334f509613d022554f281465dfcd597305c988c4b06e297e5d777afdb66c3391c3c471ebf9a1e051ba38201f08ca758d2dc83a71c34088e6785c1a775e2bde492361462cac9e7042653341cd1e190d0265a33f46ba564dc6116689cf19a8af6816c006df69803008246d44bc849babfbcc3de601fba3d10d696bf4b4d9cb8e291584e7d24bb2c81282972e71cb4493fb4966fcb483d6b62b24a0e25f912ee857d8843e4fa6181b8351f0a300e14503d51f46f367ec872712004535a56f14c65430f044f9685137a1afb2dc0aa402fde8d83b072ef0c4357529466e017dfb2935444103bbeec61bf8944924371921eefd02f35fd5283f3b7bce58a6f4ca15fb32cee8869be8d7720501ec18cc097c236b19212514582212719aede2400b1dd1ff43208ac7504bfb60a00',
        height: 862859,
        refundAmount: '8101340000000000'
      }
    ]
    for (const testCase of cases) {

      /**
       * We perform this modifications because even that these are test cases that happened with actual mainnet
       * transactions, the amounts are too small to be used in regtest, so we need to adapt them to the test environment
       * also, the LBC address is different, so we modify that value as well
       */
      const modifiedQuote = structuredClone(testCase.quote);
      const regtestMultiplier = web3.utils.toBN('100');
      modifiedQuote.lbcAddress = instance.address;
      modifiedQuote.value = testCase.quote.value.mul(regtestMultiplier);
      modifiedQuote.gasFee = testCase.quote.gasFee.mul(regtestMultiplier);
      modifiedQuote.callFee = testCase.quote.callFee.mul(regtestMultiplier);
      const modifiedRefundAmount = web3.utils.toBN(testCase.refundAmount).mul(regtestMultiplier);

      const refundAddressBalanceBefore = await web3.eth.getBalance(modifiedQuote.rskRefundAddress)
        .then(result => web3.utils.toBN(result));
      const quoteHash = await instance.hashQuote(utils.asArray(modifiedQuote));
      await bridgeMockInstance.setPegin(quoteHash, { value: modifiedRefundAmount });
      const receipt = await instance.registerPegIn(utils.asArray(modifiedQuote), '0x'+testCase.signature, '0x'+testCase.btcRawTx, '0x'+testCase.pmt, testCase.height);
      const refundAddressBalanceAfter = await web3.eth.getBalance(modifiedQuote.rskRefundAddress)
        .then(result => web3.utils.toBN(result));

      expect(receipt.logs.length).to.be.eq(2);
      expect(refundAddressBalanceAfter.sub(refundAddressBalanceBefore)).to.be.a.bignumber.eq(modifiedRefundAmount);

      truffleAssertions.eventEmitted(receipt, "Refund", {
        dest: testCase.quote.rskRefundAddress,
        amount: modifiedRefundAmount,
        success: true,
        quoteHash: quoteHash
      });
      truffleAssertions.eventEmitted(receipt, "PegInRegistered", {
        quoteHash: quoteHash,
        transferredAmount: modifiedRefundAmount
      });
    }
  });

  it("should register liquidity provider", async () => {
    let currAddr = accounts[9];
    let existing = await instance.getCollateral(currAddr);

    let tx = await instance.register(
      "First contract",
      "http://localhost/api",
      true,
      "both",
      { from: currAddr, value: utils.LP_COLLATERAL }
    );
    providerList.push(tx.logs[0].args.id.toNumber());

    let current = await instance.getCollateral(currAddr);
    let registered = current.sub(existing);

    truffleAssertions.eventEmitted(tx, "Register", {
      from: currAddr,
      amount: utils.LP_COLLATERAL,
    });
    // TODO this multiplication by 2 is a temporal fix until we define solution with product team
    expect(utils.LP_COLLATERAL).to.be.a.bignumber.eq(
      registered.mul(web3.utils.toBN(2))
    );
  });
  it("Should fail on register if bad parameters", async () => {
    let currAddr = accounts[5];

    await truffleAssertions.reverts(
      instance.register("", "", true, "both", {
        from: currAddr,
        value: utils.LP_COLLATERAL,
      }),
      "LBC010"
    );
  });
  it("should fail when Liquidity provider is already registered", async () => {
    let currAddr = accounts[4];
    let existing = await instance.getCollateral(currAddr);

    let tx = await instance.register(
        "First contract",
        "http://localhost/api",
        true,
        "both",
        { from: currAddr, value: utils.LP_COLLATERAL }
    );
    providerList.push(tx.logs[0].args.id.toNumber());

    let current = await instance.getCollateral(currAddr);
    let registered = current.sub(existing);

    truffleAssertions.eventEmitted(tx, "Register", {
      from: currAddr,
      amount: utils.LP_COLLATERAL,
    });
    expect(utils.LP_COLLATERAL).to.be.a.bignumber.eq(
        registered.mul(web3.utils.toBN(2))
    );
    await truffleAssertions.reverts(
        instance.register(
            "First contract",
            "http://localhost/api",
            true,
            "both",
            { from: currAddr, value: utils.LP_COLLATERAL }
        ),
        "LBC070"
    );
  });
  it("Should fail on register if not deposit the minimum collateral", async () => {
    let currAddr = accounts[5];

    await truffleAssertions.reverts(
      instance.register(
        "First contract",
        "http://localhost/api",
        true,
        "both",
        { from: currAddr, value: web3.utils.toBN(0) }
      ),
      "LBC008"
    );
  });

  it("should not register lp with not enough collateral", async () => {
    const minCollateral = await instance.getMinCollateral();

    const lessThanMinimum = minCollateral.sub(utils.ONE_COLLATERAL);
    await truffleAssertions.reverts(
      instance.register(
        "First contract",
        "http://localhost/api",
        true,
        "both",
        { from: accounts[1], value: lessThanMinimum }
      ),
      "LBC008"
    );
  });

  it("should fail to register liquidity provider from a contract", async () => {
    let currAddr = accounts[9];

    await truffleAssertions.fails(
      mock.callRegister(instance.address, {
        from: currAddr,
        value: utils.LP_COLLATERAL,
      })
    );
  });

  it("should get registered liquidity providers", async () => {
    let currAddr = accounts[1];

    let tx = await instance.register(
      "First contract",
      "http://localhost/api",
      true,
      "both",
      {
        from: currAddr,
        value: utils.LP_COLLATERAL,
      }
    );
    providerList.push(tx.logs[0].args.id.toNumber());

    truffleAssertions.eventEmitted(tx, "Register", {
      from: currAddr,
      amount: utils.LP_COLLATERAL,
    });
    let currAddr2 = accounts[2];

    let tx2 = await instance.register(
      "Second contract",
      "http://localhost/api",
      true,
      "both",
      {
        from: currAddr2,
        value: utils.LP_COLLATERAL,
      }
    );
    providerList.push(tx2.logs[0].args.id.toNumber());

    truffleAssertions.eventEmitted(tx2, "Register", {
      from: currAddr2,
      amount: utils.LP_COLLATERAL,
    });
    let providers = await instance.getProviders();
    expect(providers.length).to.be.greaterThan(0);
    expect(accounts).to.includes(providers[0].provider);
    expect(accounts).to.includes(providers[1].provider);
    expect(accounts).to.includes(providers[2].provider);
  });
  it("should get providerIds", async () => {
    let providerId = await instance.getProviderIds();
    expect(providerId.toNumber() == providerList.length);
  });
  it("should disable provider", async () => {
    const providerAddress = accounts[0];
    await instance.setProviderStatus(1, false, { from: providerAddress });
    const provider = await instance.getProvider(providerAddress);
    assert.equal(provider.status, false, "Provider status should be false");
  });
  describe("function getProvider should", () => {
    it("should fail if provider does not exist", async () => {
      await truffleAssertions.reverts(
        instance.getProvider(accounts[8]),
        "LBC001"
      );
    })
    it("should return correct state of the provider", async () => {
      let provider = await instance.getProvider(accounts[0]);
      expect(provider.status).to.be.false;
      expect(provider.name).to.be.equal("First contract");
      expect(provider.apiBaseUrl).to.be.equal("http://localhost/api");
      expect(provider.provider).to.be.equal(accounts[0]);
      expect(provider.providerType).to.be.equal("both");
      provider = await instance.getProvider(accounts[2]);
      expect(provider.status).to.be.true;
      expect(provider.name).to.be.equal("Second contract");
      expect(provider.apiBaseUrl).to.be.equal("http://localhost/api");
      expect(provider.provider).to.be.equal(accounts[2]);
      expect(provider.providerType).to.be.equal("both");
    })
  })
  it("should enable provider", async () => {
    const providerAddress = accounts[0];
    await instance.setProviderStatus(1, true, { from: providerAddress });
    const provider = await instance.getProvider(providerAddress);
    assert.equal(provider.status, true, "Provider status should be false");
  });
  it("should disable provider as provider owner", async () => {
    const providerAddress = accounts[0];
    await instance.setProviderStatus(1, false);
    const provider = await instance.getProvider(providerAddress);
    assert.equal(provider.status, false, "Provider status should be false");
  });
  it("should fail disabling provider as non owners", async () => {
    await truffleAssertions.reverts(
      instance.setProviderStatus(1, false, { from: accounts[1] })
    );
  });
  it("should match lp address with address retrieved from ecrecover", async () => {
    let quote = utils.getTestQuote(
      instance.address,
      accounts[1],
      "0x00",
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN(1)
    );

    let quoteHash = await instance.hashQuote(utils.asArray(quote));
    let sig = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    let signer = web3.eth.accounts.recover(quoteHash, sig);

    expect(liquidityProviderRskAddress).to.be.equal(signer);

    let sameSigner = await signatureValidatorInstance.verify(
      liquidityProviderRskAddress,
      quoteHash,
      sig
    );
    expect(sameSigner).to.be.true;
  });

  it("should call contract for user", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = mock.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[1], ["12"]);
    let quote = utils.getTestQuote(
      instance.address,
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN("20000000000000000000") // 20 RBTCs
    );

    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let peginAmount = quote.val.add(quote.callFee);
    let initialLPBalance = await instance.getBalance(
      liquidityProviderRskAddress
    );
    let initialLBCBalance = await web3.eth.getBalance(instance.address);
    let quoteHash = await instance.hashQuote(utils.asArray(quote));
    let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);

    let firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTime + 300).substring(2)
    );
    let nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTime + 600).substring(2)
    );
    let firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    let nHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      nConfirmationTime +
      "0000000000000000";

    await bridgeMockInstance.setPegin(quoteHash, { value: peginAmount });
    await bridgeMockInstance.setHeader(height, firstHeader);
    await bridgeMockInstance.setHeader(
      height + quote.depositConfirmations - 1,
      nHeader
    );
    await mock.set(0);

    let initialLPDeposit = await instance.getCollateral(
      liquidityProviderRskAddress
    );
    let cfuTx = await instance.callForUser(utils.asArray(quote), {
      value: quote.val,
    });

    let currentLPBalance = await instance.getBalance(
      liquidityProviderRskAddress
    );

    expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);

    let amount = await instance.registerPegIn.call(
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

    let finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
    let finalLBCBalance = await web3.eth.getBalance(instance.address);
    let finalLPDeposit = await instance.getCollateral(
      liquidityProviderRskAddress
    );

    let lpBal = web3.utils
      .toBN(finalLPBalance)
      .sub(web3.utils.toBN(initialLPBalance));
    let lbcBal = web3.utils
      .toBN(finalLBCBalance)
      .sub(web3.utils.toBN(initialLBCBalance));
    expect(peginAmount).to.be.a.bignumber.eq(amount);
    expect(peginAmount).to.be.a.bignumber.eq(lpBal);
    expect(peginAmount.sub(quote.productFeeAmount)).to.be.a.bignumber.eq(lbcBal);
    expect(initialLPDeposit).to.be.a.bignumber.eq(finalLPDeposit);
    truffleAssertions.eventEmitted(cfuTx, "CallForUser", {
      from: quote.liquidityProviderRskAddress,
      dest: quote.destAddr,
      value: quote.val,
      data: quote.data,
      success: true,
      quoteHash: quoteHash,
    });
    let finalValue = await mock.check();
    expect(web3.utils.toBN(12)).to.be.a.bignumber.eq(finalValue);
  });

  it("should fail when withdraw amount greater than of sender balance", async () => {
    await instance.deposit({ value: web3.utils.toBN("100000000") });
    await truffleAssertions.reverts(
      instance.withdraw(web3.utils.toBN("99999999999999999999")),
      "LBC019"
    );
    await instance.withdraw(web3.utils.toBN("100000000"));
  });

  it("should fail when liquidityProdvider try to withdraw collateral without resign postion as liquidity provider before", async () => {
    const lpAddress = accounts[6];
    await instance.register(
      "First contract",
      "http://localhost/api",
      true,
      "both",
      {
        from: lpAddress,
        value: utils.LP_COLLATERAL,
      }
    );
    await instance.addCollateral({ value: web3.utils.toBN("100000000"), from: lpAddress });

    await truffleAssertions.reverts(
      instance.withdrawCollateral({ from: lpAddress }),
      "LBC021"
    );
    await instance.resign({ from: lpAddress });
    await utils.mineBlocks(utils.RESIGN_DELAY_BLOCKS);
    await instance.withdrawCollateral({ from: lpAddress });
  });

  it("should fail when liquidityProdvider resign two times", async () => {
    const lpAddress = accounts[3];
    await instance.register(
      "First contract",
      "http://localhost/api",
      true,
      "both",
      {
        from: lpAddress,
        value: utils.LP_COLLATERAL,
      }
    );
    await instance.resign({ from: lpAddress });
    await truffleAssertions.reverts(instance.resign({ from: lpAddress }), "LBC001");
    await utils.mineBlocks(utils.RESIGN_DELAY_BLOCKS);
    await instance.withdrawCollateral({ from: lpAddress });
  });

  it("should deposit a value to increase balance of liquidity provider", async () => {
    const value = web3.utils.toBN("100000000");
    const tx = await instance.deposit({ value });
    truffleAssertions.eventEmitted(tx, "BalanceIncrease", {
      dest: liquidityProviderRskAddress,
      amount: value,
    });
  });

  it("should fail on contract call due to invalid lbc address", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = mock.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[1], ["12"]);
    let signature = "0x00";
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let quote = utils.getTestQuote(
      accounts[0], // non-LBC address
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(0)
    );

    await truffleAssertions.reverts(
      instance.hashQuote.call(utils.asArray(quote)),
      "LBC051"
    );

    await truffleAssertions.reverts(
      instance.callForUser.call(utils.asArray(quote), { value: quote.val }),
      "LBC051"
    );

    await truffleAssertions.reverts(
      instance.registerPegIn.call(
        utils.asArray(quote),
        signature,
        btcRawTransaction,
        partialMerkleTree,
        height
      ),
      "LBC051"
    );
  });

  it("should fail on contract call due to invalid contract address", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = bridgeMockInstance.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[1], ["12"]);
    let signature = "0x00";
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let quote = utils.getTestQuote(
      instance.address,
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(0)
    );

    await truffleAssertions.reverts(
      instance.hashQuote.call(utils.asArray(quote)),
      "LBC052"
    );

    await truffleAssertions.reverts(
      instance.callForUser.call(utils.asArray(quote), { value: quote.val }),
      "LBC052"
    );

    await truffleAssertions.reverts(
      instance.registerPegIn.call(
        utils.asArray(quote),
        signature,
        btcRawTransaction,
        partialMerkleTree,
        height
      ),
      "LBC052"
    );
  });

  it("should fail on contract call due to invalid user btc refund address", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = mock.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[1], ["12"]);
    let signature = "0x00";
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let quote = utils.getTestQuote(
      instance.address,
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(0)
    );
    for (let addr of [
      "0x0000000000000000000000000000000000000012" /* 20 bytes */,
      "0x00000000000000000000000000000000000000000012" /* 22 bytes */,
    ]) {
      quote.userBtcRefundAddress = addr;

      await truffleAssertions.reverts(
        instance.hashQuote.call(utils.asArray(quote)),
        "LBC053"
      );

      await truffleAssertions.reverts(
        instance.callForUser.call(utils.asArray(quote), { value: quote.val }),
        "LBC053"
      );

      await truffleAssertions.reverts(
        instance.registerPegIn.call(
          utils.asArray(quote),
          signature,
          btcRawTransaction,
          partialMerkleTree,
          height
        ),
        "LBC053"
      );
    }
  });

  it("should fail on contract call due to invalid lp btc address", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = mock.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[1], ["12"]);
    let signature = "0x00";
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let quote = utils.getTestQuote(
      instance.address,
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(0)
    );

    for (let addr of [
      "0x0000000000000000000000000000000000000012" /* 20 bytes */,
      "0x00000000000000000000000000000000000000000012" /* 22 bytes */,
    ]) {
      quote.liquidityProviderBtcAddress = addr;

      await truffleAssertions.reverts(
        instance.hashQuote.call(utils.asArray(quote)),
        "LBC054"
      );

      await truffleAssertions.reverts(
        instance.callForUser.call(utils.asArray(quote), { value: quote.val }),
        "LBC054"
      );

      await truffleAssertions.reverts(
        instance.registerPegIn.call(
          utils.asArray(quote),
          signature,
          btcRawTransaction,
          partialMerkleTree,
          height
        ),
        "LBC054"
      );
    }
  });

  it("should fail on contract call due to quote value+fee being below min peg-in", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = mock.address;
    let data = web3.eth.abi.encodeFunctionCall(mock.abi[1], ["12"]);
    let signature = "0x00";
    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let quote = utils.getTestQuote(
      instance.address,
      destAddr,
      data,
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(0)
    );
    quote.productFeeAmount = web3.utils.toBN(0)

    await truffleAssertions.reverts(
      instance.hashQuote.call(utils.asArray(quote)),
      "LBC055"
    );

    await truffleAssertions.reverts(
      instance.callForUser.call(utils.asArray(quote), { value: quote.val }),
      "LBC055"
    );

    await truffleAssertions.reverts(
      instance.registerPegIn.call(
        utils.asArray(quote),
        signature,
        btcRawTransaction,
        partialMerkleTree,
        height
      ),
      "LBC055"
    );
  });

  it("should transfer value for user", async () => {
    let rskRefundAddress = accounts[2];
    let destAddr = accounts[1];
    let lbcAddress = instance.address;
    let quote = utils.getTestQuote(
      lbcAddress,
      destAddr,
      "0x00",
      liquidityProviderRskAddress,
      rskRefundAddress,
      web3.utils.toBN(10)
    );

    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let initialUserBalance = await web3.eth.getBalance(destAddr);
    let initialLPBalance = await instance.getBalance(
      liquidityProviderRskAddress
    );
    let initialLBCBalance = await web3.eth.getBalance(instance.address);
    let peginAmount = quote.val.add(quote.callFee).add(quote.productFeeAmount).add(quote.gasFee);
    let quoteHash = await instance.hashQuote(utils.asArray(quote));
    let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    let firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTime + 300).substring(2)
    );
    let nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTime + 600).substring(2)
    );
    let firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    let nHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      nConfirmationTime +
      "0000000000000000";

    await bridgeMockInstance.setPegin(quoteHash, { value: peginAmount });
    await bridgeMockInstance.setHeader(height, firstHeader);
    await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);
    let initialLPDeposit = await instance.getCollateral(
      liquidityProviderRskAddress
    );

    let cfuTx = await instance.callForUser(utils.asArray(quote), {
      value: quote.val,
    });

    let currentLPBalance = await instance.getBalance(
      liquidityProviderRskAddress
    );
    expect(currentLPBalance).to.be.a.bignumber.eq(initialLPBalance);

    let amount = await instance.registerPegIn.call(
      utils.asArray(quote),
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );

    const registerPegin = await instance.registerPegIn(
      utils.asArray(quote),
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );

    let finalLPBalance = await instance.getBalance(liquidityProviderRskAddress);
    let finalLBCBalance = await web3.eth.getBalance(instance.address);
    let finalUserBalance = await web3.eth.getBalance(destAddr);
    let finalLPDeposit = await instance.getCollateral(
      liquidityProviderRskAddress
    );

    let lbcBal = web3.utils
      .toBN(finalLBCBalance)
      .sub(web3.utils.toBN(initialLBCBalance));
    let lpBal = web3.utils
      .toBN(finalLPBalance)
      .sub(web3.utils.toBN(initialLPBalance));
    let usrBal = web3.utils
      .toBN(finalUserBalance)
      .sub(web3.utils.toBN(initialUserBalance));
    truffleAssertions.eventEmitted(registerPegin, "DaoFeeSent", {
      quoteHash: quoteHash,
      amount: quote.productFeeAmount
    });
    truffleAssertions.eventEmitted(cfuTx, "CallForUser", {
      from: quote.liquidityProviderRskAddress,
      dest: quote.destAddr,
      value: quote.val,
      data: quote.data,
      success: true,
      quoteHash: quoteHash,
    });
    expect(peginAmount).to.be.a.bignumber.eq(amount);
    expect(usrBal).to.be.a.bignumber.eq(quote.val);
    expect(lbcBal).to.be.a.bignumber.eq(peginAmount.sub(quote.productFeeAmount));
    expect(lpBal).to.be.a.bignumber.eq(peginAmount.sub(quote.productFeeAmount));
    expect(finalLPDeposit).to.be.a.bignumber.eq(initialLPDeposit);
  });

  it("Should not generate transaction to DAO when product fee is 0 in registerPegIn", async () => {
    const daoFeeCollectorInitialBalance = await web3.eth.getBalance(accounts[8]);
    let quote = utils.getTestQuote(
      instance.address,
      accounts[1],
      "0x00",
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN(100)
    );
    quote.productFeeAmount = web3.utils.toBN(0)

    let btcRawTransaction = "0x101";
    let partialMerkleTree = "0x202";
    let height = 10;
    let peginAmount = quote.val.add(quote.callFee).add(quote.productFeeAmount).add(quote.gasFee);
    let quoteHash = await instance.hashQuote(utils.asArray(quote));
    let signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    let firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTime + 300).substring(2)
    );
    let nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTime + 600).substring(2)
    );
    let firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    let nHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      nConfirmationTime +
      "0000000000000000";

    await bridgeMockInstance.setPegin(quoteHash, { value: peginAmount });
    await bridgeMockInstance.setHeader(height, firstHeader);
    await bridgeMockInstance.setHeader(height + quote.depositConfirmations - 1, nHeader);

    await instance.callForUser(utils.asArray(quote), { value: quote.val });

    await instance.registerPegIn.call(
      utils.asArray(quote),
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );

    const registerPegin = await instance.registerPegIn(
      utils.asArray(quote),
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );

    const daoFeeCollectorFinalBalance = await web3.eth.getBalance(accounts[8]);
    expect(daoFeeCollectorFinalBalance).to.be.a.bignumber.eq(web3.utils.toBN(daoFeeCollectorInitialBalance));
    truffleAssertions.eventNotEmitted(registerPegin, "DaoFeeSent", {
      quoteHash: quoteHash,
      amount: quote.productFeeAmount
    });
  });

  it("should resign", async () => {
    let lbcAddress = instance.address;
    const lpAddress = accounts[5];
      await instance.register(
        "First contract",
        "http://localhost/api",
        true,
        "both",
        {
          from: lpAddress,
          value: utils.LP_COLLATERAL,
        }
    );
    let initialLPBalance = await instance.getBalance(
      lpAddress
    );
    let initialLBCBalance = await web3.eth.getBalance(lbcAddress);
    const initialPeginCollateral = await instance.getCollateral(lpAddress);
    const initialPegoutCollateral = await instance.getPegoutCollateral(lpAddress);
    const totalInitialCollateral = web3.utils.toBN(initialPeginCollateral.add(initialPegoutCollateral));
    let resignTx = await instance.resign({ from: lpAddress });
    let withdrawTx = await instance.withdraw(initialLPBalance, { from: lpAddress });

    const lpBalanceAfterResign = await instance.getBalance(lpAddress);
    const lbcBalanceAfterResign = await web3.eth.getBalance(lbcAddress);

    let lbcCurrBal = web3.utils
      .toBN(initialLBCBalance)
      .sub(web3.utils.toBN(lbcBalanceAfterResign));
    expect(initialLPBalance).to.be.a.bignumber.eq(lbcCurrBal);
    expect(lpBalanceAfterResign).to.be.a.bignumber.eq(web3.utils.toBN(0));

    await utils.mineBlocks(utils.RESIGN_DELAY_BLOCKS);

    const initialLpRbtc = await web3.eth.getBalance(lpAddress).then(res => web3.utils.toBN(res));
    const withdrawCollateralTx = await instance.withdrawCollateral({ from: lpAddress });
    const finalLpRbtc = await web3.eth.getBalance(lpAddress).then(res => web3.utils.toBN(res));
    const withdrawCollateralGas = web3.utils.toBN(withdrawCollateralTx.receipt.cumulativeGasUsed).mul(web3.utils.toBN(withdrawCollateralTx.receipt.effectiveGasPrice))

    const finalLpPeginCollateral = await instance.getCollateral(lpAddress);
    const finalLpPegoutCollateral = await instance.getPegoutCollateral(lpAddress);
    const totalFinalCollateral = finalLpPeginCollateral.add(finalLpPegoutCollateral);
    const finalLbcBalance = await web3.eth.getBalance(lbcAddress);
    const lbcCollateral = web3.utils
      .toBN(lbcBalanceAfterResign)
      .sub(web3.utils.toBN(finalLbcBalance));
    truffleAssertions.eventEmitted(resignTx, "Resigned", {
      from: lpAddress,
    });
    truffleAssertions.eventEmitted(withdrawTx, "Withdrawal", {
      from: lpAddress,
      amount: initialLPBalance,
    });
    truffleAssertions.eventEmitted(withdrawCollateralTx, "WithdrawCollateral", {
      from: lpAddress,
      amount: web3.utils.toBN(totalInitialCollateral.toString()),
    });
    expect(lbcCollateral).to.be.a.bignumber.eq(totalInitialCollateral);
    expect(web3.utils.toBN(0)).to.be.a.bignumber.eq(totalFinalCollateral);
    expect(finalLpRbtc.sub(initialLpRbtc).add(withdrawCollateralGas)).to.be.a.bignumber.eq(totalInitialCollateral);
  });

  ["p2pkh", "p2sh", "p2wpkh", "p2wsh", "p2tr"].forEach((scriptType) => {
    it(`Should refundPegOut for a ${scriptType.toUpperCase()} transaction `, async () => {
      await instance.addPegoutCollateral({
        value: web3.utils.toWei("30000", "wei"),
        from: liquidityProviderRskAddress,
      });
      const blockHeaderHash =
        "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
      const partialMerkleTree =
        "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
      const merkleBranchHashes = [
        "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
      ];

      const getBalances = () =>
        Promise.all([
          instance.getBalance(liquidityProviderRskAddress),
          web3.eth.getBalance(instance.address),
        ]);

      const [lpBalanceBeforeDeposit, contractBalanceBefore] = await getBalances();

      let quote = utils.getTestPegOutQuote(
        instance.address, //lbc address
        liquidityProviderRskAddress,
        accounts[2],
        web3.utils.toBN("1000000000000001"),
        scriptType
      );
      quote.transferConfirmations = 0;

      // configure mocked block on mockBridge
      const firstConfirmationTime = utils.reverseHexBytes(
        web3.utils.toHex(quote.agreementTimestamp + 100).substring(2)
      );
      const firstHeader =
        "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
        firstConfirmationTime +
        "0000000000000000";
      await bridgeMockInstance.setHeaderByHash(blockHeaderHash, firstHeader);

      const quoteHash = await instance.hashPegoutQuote(utils.asArray(quote));
      const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
      const msgValue = quote.value.add(quote.callFee).add(quote.productFeeAmount).add(quote.gasFee);
      const pegOut = await instance.depositPegout(utils.asArray(quote), signature, {
        value: msgValue.toNumber()
      });
      await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");

      const btcTx = await utils.generateRawTx(instance, quote, scriptType);
      const [lpBalanceAfterDeposit, contractBalanceAfter] = await getBalances();

      expect(lpBalanceBeforeDeposit.toString()).to.be.eq(
        lpBalanceAfterDeposit.toString()
      );
      expect(+contractBalanceAfter).to.be.eq(+contractBalanceBefore + msgValue.toNumber());

      const lpBalanceBeforeRefund = await web3.eth.getBalance(
        liquidityProviderRskAddress
      );
      const refund = await instance.refundPegOut(
        quoteHash,
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      const lpBalanceAfterRefund = await web3.eth.getBalance(
        liquidityProviderRskAddress
      );
      const usedInGas = refund.receipt.gasUsed * refund.receipt.effectiveGasPrice;
      const refundedAmount = quote.value.add(quote.callFee).add(quote.gasFee);
      truffleAssertions.eventEmitted(refund, "DaoFeeSent", {
        quoteHash: quoteHash,
        amount: quote.productFeeAmount
      });
      expect(lpBalanceAfterRefund).to.be.a.bignumber.eq(
        web3.utils.toBN(lpBalanceBeforeRefund).add(refundedAmount).sub(web3.utils.toBN(usedInGas))
      );
      truffleAssertions.eventEmitted(refund, "PegOutRefunded", { quoteHash });
    });
  });

  it("Should refundPegOut with wrong rounding", async () => {
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    const getBalances = () =>
      Promise.all([
        instance.getBalance(liquidityProviderRskAddress),
        web3.eth.getBalance(instance.address),
      ]);

    const [userPegInBalanceBefore, contractBalanceBefore] = await getBalances();

    const now = Math.floor(Date.now() / 1000);
    const quote = {
      lbcAddress: instance.address,
      liquidityProviderRskAddress: liquidityProviderRskAddress,
      btcRefundAddress: bs58check.decode("2Mxo7RNBLYVxFhiz4MHbr1UyDWgzCReBRBx"),
      rskRefundAddress: "0x399F56CD72CA88f3873b3698A395083A44a9A641",
      lpBtcAddr: bs58check.decode("mfdi3vowMn2YRTSmXKTNvg4PWAZCaeLjHZ"),
      callFee: web3.utils.toBN("300000000000000"),
      penaltyFee: web3.utils.toBN("10000000000000"),
      nonce: web3.utils.toBN("154806842258897340"),
      depositAddr: bs58check.decode("2Mxo7RNBLYVxFhiz4MHbr1UyDWgzCReBRBx"),
      value: web3.utils.toBN("72160329123080000"),
      agreementTimestamp: now,
      depositDateLimit: now + 3600,
      depositConfirmations: 10,
      transferConfirmations: 2,
      transferTime: 3600,
      expireDate: now + 10800,
      expireBlocks: 6946482,
      gasFee: web3.utils.toBN("11290000000000"),
      productFeeAmount: web3.utils.toBN("0")
    };

    // configure mocked block on mockBridge
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 100).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeaderByHash(blockHeaderHash, firstHeader);

    const quoteHash = await instance.hashPegoutQuote(utils.asArray(quote));
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const msgValue = quote.value.add(quote.callFee).add(quote.productFeeAmount).add(quote.gasFee);
    await instance.depositPegout(utils.asArray(quote), signature, { value: msgValue });

    const btcTx = `0x0200000001c58d201925a80f49c3160bd97be969453d64c311d7c7a2c2c31318fdeedb8eb7020000006a47304402201944d92c0afd1524ac763c709269f70ca3a7597deffa8d732dad5fb1318ff5bc02205970622ade1d31212ad95ee62926d0acdf7e61e481c118acd02b9c9d29e9913b012102361cffc83b11d361119acd4e57c7103f94bce4ee990e3f2d3fac19017fe076bffdffffff03a01b6e000000000017a9143ce07516dd6c85b69b4abec139fbac01cf84fec0870000000000000000226a20${quoteHash.slice(2)}ba9db202000000001976a9140147059622479e482bc1bf7f7ca8433bbfc3a34888ac00000000`;
    const [userPegInBalanceAfter, contractBalanceAfter] = await getBalances();

    expect(userPegInBalanceBefore.toString()).to.be.eq(userPegInBalanceAfter.toString());
    expect(contractBalanceAfter.toString()).to.be.eq(web3.utils.toBN(contractBalanceBefore).add(msgValue).toString());

    const lpBalanceBefore = await web3.eth.getBalance(liquidityProviderRskAddress);
    const refund = await instance.refundPegOut(
      quoteHash,
      btcTx,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes
    );
    const lpBalanceAfter = await web3.eth.getBalance(liquidityProviderRskAddress);
    const usedInGas = refund.receipt.gasUsed * refund.receipt.effectiveGasPrice;
    const refundedAmount = quote.value.add(quote.callFee);
    expect(lpBalanceAfter).to.be.a.bignumber.eq(
      web3.utils.toBN(lpBalanceBefore).add(refundedAmount).sub(web3.utils.toBN(usedInGas))
    );
    truffleAssertions.eventEmitted(refund, "PegOutRefunded");
  });

  it("Should not generate transaction to DAO when product fee is 0 in refundPegOut", async () => {
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    const daoFeeCollectorBefore = await web3.eth.getBalance(accounts[8]);
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000001234567899")
    );
    quote.transferConfirmations = 0;
    quote.productFeeAmount = web3.utils.toBN(0);

    // configure mocked block on mockBridge
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 100).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeaderByHash(blockHeaderHash, firstHeader);

    const quoteHash = await instance.hashPegoutQuote(utils.asArray(quote));
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const msgValue = quote.value.add(quote.callFee).add(quote.gasFee);
    const pegOut = await instance.depositPegout(utils.asArray(quote), signature, {
      value: msgValue.toNumber()
    });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");

    const btcTx = await utils.generateRawTx(instance, quote);
    const refund = await instance.refundPegOut(
      quoteHash,
      btcTx,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes
    );
    const daoFeeCollectorAfter = await web3.eth.getBalance(accounts[8]);
    expect(daoFeeCollectorBefore).to.be.a.bignumber.eq(daoFeeCollectorAfter)
    truffleAssertions.eventNotEmitted(refund, "DaoFeeSent");
  });

  it("Should not allow user to re deposit a refunded quote", async () => {
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000000000000001")
    );
    quote.transferConfirmations = 0;
    quote.agreementTimestamp = Math.round(new Date().getTime() / 1000)

    // configure mocked block on mockBridge
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 300).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeaderByHash(blockHeaderHash, firstHeader);

    const quoteHash = await instance.hashPegoutQuote(utils.asArray(quote));
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const msgValue = quote.value.add(quote.callFee).add(quote.productFeeAmount).add(quote.gasFee);
    const pegOut = await instance.depositPegout(utils.asArray(quote), signature, { value: msgValue.toNumber() });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");

    const btcTx = await utils.generateRawTx(instance, quote);
    const refund = await instance.refundPegOut(
      quoteHash,
      btcTx,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes
    );
    truffleAssertions.eventEmitted(refund, "PegOutRefunded");

    const secondDeposit = instance.depositPegout(utils.asArray(quote), signature, { value: msgValue.toNumber() });
    await truffleAssertions.reverts(secondDeposit, "LBC064");
  });

  it("Should validate that the quote was processed on refundPegOut", async () => {
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    const btcTxHash =
      "0xa0cad11b688340cfbb8515d4deb7d37a8c67ea70a938578295f28b6cd8b5aade";
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    let quote = utils.getTestPegOutQuote(
      instance.address,
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000000000000001")
    );
    quote.transferConfirmations = 0;

    const quoteHash = await instance.hashPegoutQuote(utils.asArray(quote));
    const refund = instance.refundPegOut(
      quoteHash,
      btcTxHash,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes
    );
    await truffleAssertions.reverts(refund, "LBC042");
  });

  it("Should revert if LP tries to refund a pegout thats already been refunded by user", async () => {
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000000000000000")
    );
    // so its expired after deposit
    quote.expireBlock = await web3.eth.getBlock("latest").then(block => block.number + 1);
    quote.expireDate = Math.round(new Date().getTime() / 1000);

    const quoteHash = await instance.hashPegoutQuote(quote);
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const msgValue = quote.value.add(quote.callFee);
    const pegOut = await instance.depositPegout(quote, signature, {
      value: msgValue.toNumber()
    });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");

    await utils.timeout(2000);
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    await web3.eth.getBlock("latest")
    const tx = await instance.refundUserPegOut(quoteHash);
    await truffleAssertions.eventEmitted(tx, "PegOutUserRefunded");

    const btcTx = await utils.generateRawTx(instance, quote);
    const refund = instance.refundPegOut(
      quoteHash,
      btcTx,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes
    );

    await truffleAssertions.reverts(refund, "LBC064");
  });

  it("Should penalize LP if refunds after expiration", async () => {
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];
    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000000000000000")
    );

    // configure mocked block on mockBridge
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 300).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeaderByHash(blockHeaderHash, firstHeader);

    // so its expired after deposit
    quote.transferConfirmations = 0
    quote.expireBlock = await web3.eth.getBlock("latest").then(block => block.number + 1);
    quote.expireDate = Math.round(new Date().getTime() / 1000);

    const quoteHash = await instance.hashPegoutQuote(utils.asArray(quote));
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const msgValue = quote.value.add(quote.callFee).add(quote.productFeeAmount).add(quote.gasFee);
    const pegOut = await instance.depositPegout(utils.asArray(quote), signature, {
      value: msgValue.toNumber()
    });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");

    await utils.timeout(2000);
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    await web3.eth.getBlock("latest")

    const btcTx = await utils.generateRawTx(instance, quote);
    const refund = await instance.refundPegOut(
      quoteHash,
      btcTx,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes
    );
    truffleAssertions.eventEmitted(refund, "PegOutRefunded");
    truffleAssertions.eventEmitted(refund, "Penalized");
  });

  it("should fail if provider is not registered for pegout on refundPegout", async () => {
    const btcTxHash =
      "0xa0cad11b688340cfbb8515d4deb7d37a8c67ea70a938578295f28b6cd8b5aade";
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];

    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[4],
      web3.utils.toBN("1000000000000000")
    );
    quote.transferConfirmations = 0;

    // configure mocked block on mockBridge
    const block = await web3.eth.getBlock("latest");
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 300).substring(2)
    );
    const nConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 600).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    const nHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      nConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeader(block.timestamp, firstHeader);
    await bridgeMockInstance.setHeader(
      block.timestamp + quote.depositConfirmations - 1,
      nHeader
    );

    await web3.eth.getBlock("latest");
    const quoteHash = await instance.hashPegoutQuote(quote);
    const refund = instance.refundPegOut(
      quoteHash,
      btcTxHash,
      blockHeaderHash,
      partialMerkleTree,
      merkleBranchHashes,
      {
        from: accounts[7],
      }
    );
    await truffleAssertions.reverts(refund, "LBC001");
  });

  it("Should emit event when pegout is deposited", async () => {
    const quote = utils.getTestPegOutQuote(
        instance.address, //lbc address
        liquidityProviderRskAddress,
        accounts[2],
        web3.utils.toBN("1000000000000000")
      );
    const value = web3.utils.toBN("500")
    const quoteHash = await instance.hashPegoutQuote(quote);
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const tx = await instance.depositPegout(
      quote,
      signature,
      { value: value.toNumber() }
    );
    await truffleAssertions.eventEmitted(tx, "PegOutDeposit", {
      quoteHash: quoteHash,
      amount: value,
    });
    // deposit again an expect an error to ensure quote is stored
    const failedTx = instance.depositPegout(quote, signature, { value: value.toNumber() });
    await truffleAssertions.reverts(failedTx, "LBC028");
  });

  it("Should not allow to deposit less than total required on pegout", async () => {
    const quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      1000
    );

    const quoteHash = await instance.hashPegoutQuote(quote);
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const valueToDeposit = 500
    const tx = instance.depositPegout(
      quote,
      signature,
      { value: valueToDeposit }
    );

    await truffleAssertions.reverts(tx, "LBC063");
  });

  it("Should not allow to deposit pegout if quote expired", async () => {
    const quoteExpiredByBlocks = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000000000000000")
    );

    const quoteHash = await instance.hashPegoutQuote(quoteExpiredByBlocks);
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    quoteExpiredByBlocks.expireBlock = await web3.eth.getBlock("latest").then(block => block.number - 1);
    const valueToDeposit = 2000
    const revertByBlocks = instance.depositPegout(
      quoteExpiredByBlocks,
      signature,
      { value: valueToDeposit }
    );

    await truffleAssertions.reverts(revertByBlocks, "LBC047");

    const quoteExpiredByTime = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000000000000000")
    );
    quoteExpiredByTime.expireDate = quoteExpiredByTime.agreementTimestamp;
    const revertByTime = instance.depositPegout(
      quoteExpiredByTime,
      signature,
      { value: valueToDeposit }
    );

    await truffleAssertions.reverts(revertByTime, "LBC046");
  });

  it("Should not allow to deposit pegout after deposit date limit", async () => {
    const quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000000000000000")
    );

    quote.depositDateLimit = quote.agreementTimestamp;
    const quoteHash = await instance.hashPegoutQuote(quote);
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const valueToDeposit = 2000
    const tx = instance.depositPegout(quote, signature, { value: valueToDeposit });

    await truffleAssertions.reverts(tx, "LBC065");
  });

  it("Should not allow to deposit the same quote twice", async () => {
    const quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      1000
    );

    const quoteHash = await instance.hashPegoutQuote(quote);
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    await instance.depositPegout(
      quote,
      signature,
      { value: 1500 }
    );

    const tx = instance.depositPegout(
      quote,
      signature,
      { value: 1500 }
    );

    await truffleAssertions.reverts(tx, "LBC028");
  });


  it("Should fail if provider is not registered", async () => {
    const lpAddress = accounts[7];
    await instance.register(
      "First contract",
      "http://localhost/api",
      true,
      "both",
      {
        from: lpAddress,
        value: utils.LP_COLLATERAL,
      }
    );
    const quote = utils.getTestPegOutQuote(
        instance.address, //lbc address
        lpAddress,
        accounts[2],
        web3.utils.toBN("3000000000000000")
      );
    await instance.resign({ from: lpAddress });
    await utils.mineBlocks(utils.RESIGN_DELAY_BLOCKS);
    await instance.withdrawCollateral({ from: lpAddress });
    const quoteHash = await instance.hashPegoutQuote(quote);
    const signature = await web3.eth.sign(quoteHash, lpAddress);
    const tx = instance.depositPegout(quote, signature, { value: web3.utils.toBN("500"), from: lpAddress });
    await truffleAssertions.reverts(tx, "LBC037");
  });

  it("Should refund user", async () => {
    const quoteValue = web3.utils.toBN("4");
    const penaltyValue = web3.utils.toBN("2");

    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[1],
      quoteValue.toNumber()
    );
    quote.penaltyFee = penaltyValue.toNumber();

    // so its expired after deposit
    quote.expireBlock = await web3.eth.getBlock("latest").then(block => block.number + 1);
    quote.expireDate = Math.round(new Date().getTime() / 1000) + 1;

    const quoteHash = await instance.hashPegoutQuote(quote);

    const signature = await web3.eth.sign(
      quoteHash,
      liquidityProviderRskAddress
    );


    const depositAmount = web3.utils.toBN("5");
    const firstTx = await instance.depositPegout(quote, signature, { value: depositAmount.toNumber() });

    await truffleAssertions.eventEmitted(firstTx, "PegOutDeposit", {
      quoteHash: quoteHash,
      amount: depositAmount,
    });
    // this is to wait for the quote to expire
    await utils.timeout(2500);
    await instance.addPegoutCollateral({
      value: web3.utils.toWei("30000", "wei"),
      from: liquidityProviderRskAddress,
    });
    await web3.eth.getBlock("latest")

    const balanceBefore = await web3.eth.getBalance(quote.rskRefundAddress);
    const balanceBeforeBN = web3.utils.toBN(balanceBefore);

    const tx = await instance.refundUserPegOut(quoteHash);

    const balanceAfter = await web3.eth.getBalance(quote.rskRefundAddress);
    const balanceAfterBN = web3.utils.toBN(balanceAfter);

    const dif = balanceAfterBN.sub(balanceBeforeBN);

    expect(dif.toNumber()).to.be.eq(quoteValue.toNumber());

    await truffleAssertions.eventEmitted(tx, "Penalized", {
      quoteHash: quoteHash,
      penalty:   penaltyValue,
      liquidityProvider: quote.lpRskAddress,
    });

    await truffleAssertions.eventEmitted(tx, "PegOutUserRefunded", {
      quoteHash: quoteHash,
      value: quoteValue,
      userAddress: quote.rskRefundAddress,
    });
  });

  it("Should validate if user had not deposited yet", async () => {
    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[1],
      web3.utils.toBN("1000000000000000")
    );

    // so its always expired
    quote.expireDate = quote.agreementTimestamp
    quote.expireBlock = 1

    const quoteHash = await instance.hashPegoutQuote(utils.asArray(quote));

    const tx = instance.refundUserPegOut(quoteHash);

    await truffleAssertions.reverts(tx, "LBC042");
  });

  it("Should parse raw btc transaction pay to address script", async () => {
    const firstRawTX = "0x0100000001013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40000000006a47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4ffffffff0200879303000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac0000000000000000426a403938343934346435383039323135366335613139643936356239613735383530326536646263326439353337333135656266343839373336333134656233343700000000";
    const firstTxOutputs = await btcUtils.getOutputs(firstRawTX);

    const firstNullScript = await btcUtils.parseNullDataScript(firstTxOutputs[1].pkScript);
    const firstDestinationAddress = await btcUtils.parsePayToPubKeyHash(firstTxOutputs[0].pkScript, false);
    const firstValue = firstTxOutputs[0].value;
    const firstHash = await btcUtils.hashBtcTx(firstRawTX);

    const secondRawTX = "0x01000000010178a1cf4f2f0cb1607da57dcb02835d6aa8ef9f06be3f74cafea54759a029dc000000006a473044022070a22d8b67050bee57564279328a2f7b6e7f80b2eb4ecb684b879ea51d7d7a31022057fb6ece52c23ecf792e7597448c7d480f89b77a8371dca4700a18088f529f6a012103ef81e9c4c38df173e719863177e57c539bdcf97289638ec6831f07813307974cffffffff02801d2c04000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac0000000000000000426a406539346138393731323632396262633966636364316630633034613237386330653130353265623736323666393365396137663130363762343036663035373600000000";
    const secondTxOutputs = await btcUtils.getOutputs(secondRawTX);

    const secondNullScript = await btcUtils.parseNullDataScript(secondTxOutputs[1].pkScript);
    const secondDestinationAddress = await btcUtils.parsePayToPubKeyHash(secondTxOutputs[0].pkScript, true);
    const secondValue = secondTxOutputs[0].value;
    const secondHash = await btcUtils.hashBtcTx(secondRawTX);

    expect(firstNullScript).to.eq("0x4039383439343464353830393231353663356131396439363562396137353835303265366462633264393533373331356562663438393733363331346562333437");
    expect(firstDestinationAddress).to.eq("0x6f3c5f66fe733e0ad361805b3053f23212e5755c8d");
    expect(firstValue).to.eq("60000000");
    expect(firstHash).to.eq("0x03c4522ef958f724a7d2ffef04bd534d9eca74ffc0b28308797d2853bc323ba6");

    expect(secondNullScript).to.eq("0x4065393461383937313236323962626339666363643166306330346132373863306531303532656237363236663933653961376631303637623430366630353736");
    expect(secondDestinationAddress).to.eq("0x003c5f66fe733e0ad361805b3053f23212e5755c8d");
    expect(secondValue).to.eq("70000000");
    expect(secondHash).to.eq("0xfd4251485dafe36aaa6766b38cf236b5925f23f12617daf286e0e92f73708aa3");
  });

  it("Should fail on refundPegout if btc tx has op return with incorrect quote hash", async () => {
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];
    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000000000000000")
    );
    quote.transferConfirmations = 0;

    // configure mocked block on mockBridge
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 300).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeaderByHash(blockHeaderHash, firstHeader);

    const msgValue = quote.value.add(quote.callFee);
    const quoteHash = await instance.hashPegoutQuote(quote);
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const pegOut = await instance.depositPegout(quote, signature, {
      value: msgValue.toNumber()
    });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");

    quote.transferConfirmations = 5; // to generate another hash
    const btcTx = await utils.generateRawTx(instance, quote);
    quote.transferConfirmations = 0;

    await truffleAssertions.reverts(
      instance.refundPegOut(
        quoteHash,
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      ),
      "LBC069"
    );
  });

  it("Should fail on refundPegout if btc tx null data script has wrong format", async () => {
    const blockHeaderHash =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree =
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];
    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000000000000000")
    );
    quote.transferConfirmations = 0;

    // configure mocked block on mockBridge
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 300).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
      firstConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeaderByHash(blockHeaderHash, firstHeader);

    const msgValue = quote.value.add(quote.callFee).add(quote.productFeeAmount).add(quote.gasFee);
    const quoteHash = await instance.hashPegoutQuote(utils.asArray(quote));
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const pegOut = await instance.depositPegout(utils.asArray(quote), signature, {
      value: msgValue.toNumber()
    });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");

    let incorrectSizeByteTx = await utils.generateRawTx(instance, quote);
    incorrectSizeByteTx = incorrectSizeByteTx.replace("6a20", "6a40");
    await truffleAssertions.reverts(
      instance.refundPegOut(
        quoteHash,
        incorrectSizeByteTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      ),
      "LBC075"
    );

    let incorrectHashSizeTx = await utils.generateRawTx(instance, quote);
    incorrectHashSizeTx = incorrectHashSizeTx.replace("226a20"+quoteHash.slice(2), "216a19"+quoteHash.slice(2, -2));
    await truffleAssertions.reverts(
      instance.refundPegOut(
        quoteHash,
        incorrectHashSizeTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      ),
      "LBC075"
    );
  });

  it("Should fail on refundPegout if btc tx doesn't have correct amount", async () => {
    const blockHeaderHash = "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree = "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];
    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000010000000001")
    );
    quote.transferConfirmations = 0;
    quote.callFee = web3.utils.toBN(1);

    // configure mocked block on mockBridge
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 300).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
    firstConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeaderByHash(blockHeaderHash, firstHeader);

    const msgValue = quote.value.add(quote.callFee).add(quote.productFeeAmount).add(quote.gasFee);
    const quoteHash = await instance.hashPegoutQuote(utils.asArray(quote));
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const pegOut = await instance.depositPegout(utils.asArray(quote), signature, { value: msgValue.toNumber() });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");
    const btcTx = await utils.generateRawTx(instance, quote);

    await truffleAssertions.reverts(
      instance.refundPegOut(
        quoteHash,
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      ), "LBC067");
  });

  it("Should fail on refundPegout if btc tx doesn't have correct destination", async () => {
    const blockHeaderHash = "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
    const partialMerkleTree = "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
    const merkleBranchHashes = [
      "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
    ];
    let quote = utils.getTestPegOutQuote(
      instance.address, //lbc address
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN("1000000000000000")
    );
    quote.transferConfirmations = 0;
    quote.deposityAddress = bs58check.decode("msMgk6qaS5sso4CTao22VaUY8rbFPp3ThT");
    const errorQuote = structuredClone(quote)
    errorQuote.deposityAddress = bs58check.decode("mfWxJ45yp2SFn7UciZyNpvDKrzbhyfKrY8"); // any wrong destination
    // configure mocked block on mockBridge
    const firstConfirmationTime = utils.reverseHexBytes(
      web3.utils.toHex(quote.agreementTimestamp + 300).substring(2)
    );
    const firstHeader =
      "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
    firstConfirmationTime +
      "0000000000000000";
    await bridgeMockInstance.setHeaderByHash(blockHeaderHash, firstHeader);

    const msgValue = quote.value.add(quote.callFee).add(quote.productFeeAmount).add(quote.gasFee);
    const quoteHash = await instance.hashPegoutQuote(utils.asArray(quote));
    const signature = await web3.eth.sign(quoteHash, liquidityProviderRskAddress);
    const pegOut = await instance.depositPegout(utils.asArray(quote), signature, {
      value: msgValue.toNumber()
    });
    await truffleAssertions.eventEmitted(pegOut, "PegOutDeposit");
    let btcTx = await utils.generateRawTx(instance, errorQuote);
    const errorQuoteHash = await instance.hashPegoutQuote(utils.asArray(errorQuote));
    btcTx = btcTx.replace(errorQuoteHash.slice(2), quoteHash.slice(2));

    await truffleAssertions.reverts(
      instance.refundPegOut(
        quoteHash,
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      ), "LBC068");
  });

  it('Should parse btc raw transaction outputs correctly', async () => {
    const transactions = [
      {
        raw: '0x01000000000101f73a1ea2f2cec2e9bfcac67b277cc9e4559ed41cfc5973c154b7bdcada92e3e90100000000ffffffff029ea8ef00000000001976a9141770fa9929eee841aee1bfd06f5f0a178ef6ef5d88acb799f60300000000220020701a8d401c84fb13e6baf169d59684e17abd9fa216c8cc5b9fc63d622ff8c58d0400473044022051db70142aac24e8a13050cb0f61183704a7fe572c41a09caf5e7f56b7526f87022017d1a4b068a32af3dcea2d9a0e2f0d648c9f0f7fb01698d83091fd5b57f69ade01473044022028f29f5444ea4be2db3c6895e1414caa5cee9ab79faf1bf9bc12191f421de37102205af1df5158aa9c666f2d8d4d7c9da1ef96d28277f5d4b7c193e93e243a6641ae016952210375e00eb72e29da82b89367947f29ef34afb75e8654f6ea368e0acdfd92976b7c2103a1b26313f430c4b15bb1fdce663207659d8cac749a0e53d70eff01874496feff2103c96d495bfdd5ba4145e3e046fee45e84a8a48ad05bd8dbb395c011a32cf9f88053ae00000000',
        outputs:[
          {
            value: web3.utils.toBN('15706270'),
            pkScript: '0x76a9141770fa9929eee841aee1bfd06f5f0a178ef6ef5d88ac',
            scriptSize: 25,
            totalSize: 34
          },
          {
            value: web3.utils.toBN('66492855'),
            pkScript: '0x0020701a8d401c84fb13e6baf169d59684e17abd9fa216c8cc5b9fc63d622ff8c58d',
            scriptSize: 34,
            totalSize: 43
          }
        ]
      },
      {
        raw: '0x010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff1a03583525e70ee95696543f47000000002f4e696365486173682fffffffff03c01c320000000000160014b0262460a83e78d991795007477d51d3998c70629581000000000000160014d729e8dba6f86b5c8d7b3066fd4d7d0e21fd079b0000000000000000266a24aa21a9edf052bd805f949d631a674158664601de99884debada669f237cf00026c88a5f20120000000000000000000000000000000000000000000000000000000000000000000000000',
        outputs:[
          {
            value: web3.utils.toBN('3284160'),
            pkScript: '0x0014b0262460a83e78d991795007477d51d3998c7062',
            scriptSize: 22,
            totalSize: 31
          },
          {
            value: web3.utils.toBN('33173'),
            pkScript: '0x0014d729e8dba6f86b5c8d7b3066fd4d7d0e21fd079b',
            scriptSize: 22,
            totalSize: 31
          },
          {
            value: web3.utils.toBN('0'),
            pkScript: '0x6a24aa21a9edf052bd805f949d631a674158664601de99884debada669f237cf00026c88a5f2',
            scriptSize: 38,
            totalSize: 47
          }
        ]
      },
      {
        raw: '0x0100000000010fe0305a97189636fb57126d2f77a6364a5c6a809908270583438b3622dce6bc050000000000ffffffff6d487f63c4bd89b81388c20aeab8c775883ed56f11f509c248a7f00cdc64ae940000000000ffffffffa3d3d42b99de277265468acca3c081c811a9cc7522827aa95aeb42653c15fc330000000000ffffffffd7818dabb051c4db77da6d49670b0d3f983ba1d561343027870a7f3040af44fe0000000000ffffffff72daa44ef07b8d85e8ef8d9f055e07b5ebb8e1ba6a876e17b285946eb4ea9b9b0000000000ffffffff5264480a215536fd00d229baf1ab8c7c65ce10f37b783ca9700a828c3abc952c0000000000ffffffff712209f13eee0b9f3e6331040abcc09df750e4a287128922426d8d5c78ac9fc50000000000ffffffff21c5cf14014d28ec43a58f06f8e68c52c524a2b47b3be1c5800425e1f35f488d0000000000ffffffff2898464f9eb34f1d77fde2ed75dd9ae9c258f76030bb33be8e171d3e5f3b56390000000000ffffffffd27a5adff11cffc71d88face8f5adc2ce43ad648a997a5d54c06bcdec0e3eb5c0000000000ffffffff5217ca227f0e7f98984f19c59f895a3cfa7b05cb46ed844e2b0a26c9f5168d7a0000000000ffffffff8384e811f57e4515dd79ebfacf3a653200caf77f115bb6d4efe4bc534f0a39dd0000000000ffffffffd0448e1aae0ea56fab1c08dae1bdfe16c46f8ae8cec6042f6525bb7c1da0fa380000000000ffffffff5831c6df8395e3dc315af82c758c622156e2c40d677dececb717f4f20ded28a90000000000ffffffff56c2ffb0554631cff11e3e3fa90e6f35e76f420b29cde1faaa68c07cd0c6f8030100000000ffffffff02881300000000000016001463052ae51729396821a0cd91e0b1e9c61f53e168424e0800000000001600140d76db7b4f8f93a0b445bd782df2182a3e577604024730440220260695f8cf81168b46a24a07c380fd2568ee72f939309ed710e055f146d267db022044813ec9d65a57c8d4298b0bd9600664c3875bd2230b6a376a6fc70577a222bb012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100e0ed473c35a937d0b4d1a5e08f8e61248e80f5fe108c9b8b580792df8675a05d02202073dfd0d44d28780ee321c8a2d18da8157055d37d68793cbe8c53cc1c0a5321012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302473044022034e28210fe7a14dde84cdb9ef4cf0a013bbc027deebcb56232ff2dabb25c12dc02202f4ff4df794ad3dbcfa4d498ec6d0c56b22c027004767851e3b8ffc5652ba529012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302473044022030d5f4ffddf70a6086269ce982bff38c396831d0b5ef5205c3e557059903b2550220575bcf3b233c12b383bf2f16cd52e2fff2c488f0aa29ab3dec22b85b536b1c83012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100cc07265538f0ea4a8b999450549a965b0cc784371cac42cbcf8f49fbabf72b7c02207ef68377d7c6d3817d7c1a7a7936392b7043189ab1aed81eb0a7a3ad424bdcaf012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230248304502210085a8855abe9fd6680cb32911db66914cf970a30f01ecd17c7527fc369bb9f24002206da3457505a514a076954a2e5756fcc14c9e8bdc18301469dfe5b2b6daef723f012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100d4e1963f5945dfae7dc73b0af1c65cf9156995a270164c2bcbc4a539130ac268022054464ea620730129ebaf95202f96f0b8be74ff660fcd748b7a107116e01730f3012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402207a5386c7b8bf3cf301fed36e18fe6527d35bc02007afda183e81fc39c1c8193702203207a6aa2223193a5c75ed8df0e046d390dbf862a3d0da1b2d0f300dfd42e8a7012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100c8db534b9ed20ce3a91b01b03e97a8f60853fbc16d19c6b587f92455542bc7c80220061d61d1c49a3f0dedecefaafc51526325bca972e99aaa367f2ebcab95d42395012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100f5287807debe8fc2eeee7adc5b7da8a212166a4580b8fdcf402c049a40b24fb7022006cb422492ba3b1ec257c64e74f3d439c00351f05bc05e88cab5cd9d4a7389b0012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402202edb544a679791424334e3c6a85613482ca3e3d16de0ca0d41c54babada8d4a2022025d0c937221161593bd9858bb3062216a4e55d191a07323104cfef1c7fcf5bc6012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402201a6cf02624884d4a1927cba36b2b9b02e1e6833a823204d8670d71646d2dd2c40220644176e293982f7a4acb25d79feda904a235f9e2664c823277457d33ccbaa6dc012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100d49488c21322cd9a7c235ecddbd375656d98ba1ca06a5284c8c2ffb6bcbba83b02207dab29958d7c1b2466d5b5502b586d7f3d213b501689d42a313de91409179899012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100f36565200b245429afb9cdc926510198893e057e5244a7dabd94bedba394789702206786ea4033f5e1212cee9a59fb85e89b6f7fe686ab0a3b8874e77ea735e7c3b5012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402206ff3703495e0d872cbd1332d20ee39c14de6ed5a14808d80327ceedfda2329e102205da8497cb03776d5df8d67dc16617a6a3904f7abf85684a599ed6c60318aa3be012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2300000000',
        outputs:[
          {
            value: web3.utils.toBN('5000'),
            pkScript: '0x001463052ae51729396821a0cd91e0b1e9c61f53e168',
            scriptSize: 22,
            totalSize: 31
          },
          {
            value: web3.utils.toBN('544322'),
            pkScript: '0x00140d76db7b4f8f93a0b445bd782df2182a3e577604',
            scriptSize: 22,
            totalSize: 31
          }
        ]
      },
      {
        raw: '0x01000000010178a1cf4f2f0cb1607da57dcb02835d6aa8ef9f06be3f74cafea54759a029dc000000006a473044022070a22d8b67050bee57564279328a2f7b6e7f80b2eb4ecb684b879ea51d7d7a31022057fb6ece52c23ecf792e7597448c7d480f89b77a8371dca4700a18088f529f6a012103ef81e9c4c38df173e719863177e57c539bdcf97289638ec6831f07813307974cffffffff02801d2c04000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac0000000000000000426a406539346138393731323632396262633966636364316630633034613237386330653130353265623736323666393365396137663130363762343036663035373600000000',
        outputs:[
          {
            value: web3.utils.toBN('70000000'),
            pkScript: '0x76a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac',
            scriptSize: 25,
            totalSize: 34
          },
          {
            value: web3.utils.toBN('0'),
            pkScript: '0x6a4065393461383937313236323962626339666363643166306330346132373863306531303532656237363236663933653961376631303637623430366630353736',
            scriptSize: 66,
            totalSize: 75
          }
        ]
      },
      {
        raw: '0x020000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff050261020101ffffffff02205fa012000000001976a91493fa9b864d39108a311918320e2a804de2e946f688ac0000000000000000266a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf90120000000000000000000000000000000000000000000000000000000000000000000000000',
        outputs:[
          {
            value: web3.utils.toBN('312500000'),
            pkScript: '0x76a91493fa9b864d39108a311918320e2a804de2e946f688ac',
            scriptSize: 25,
            totalSize: 34
          },
          {
            value: web3.utils.toBN('0'),
            pkScript: '0x6a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf9',
            scriptSize: 38,
            totalSize: 47
          }
        ]
      },
      {
        raw: '0x020000000001010e02566bfc272aed951a7f68152707fd14d29aaf2fe4c8106e623faec848437c0000000000fdffffff02dba01800000000001976a914b2978fcacc03e34dae7b0d9ef112a7b3e5c0bdc488ac03a10185120000001976a9142591f7537994333dc2c119a88defb5b53d34495188ac0247304402205bdb0dfbbeb0ffc7f2d86cd1026a893252f49399d22876dfe6f3ff1ce723507502200f155b8fab03352aec2b07bbd0e0ab147454937f34301518b428af7c6216b79d01210249b9c2a173ec4c9bfae80edf85fa48ff9e196856bf7f48f2208800760bb28d07d4322500',
        outputs:[
          {
            value: web3.utils.toBN('1614043'),
            pkScript: '0x76a914b2978fcacc03e34dae7b0d9ef112a7b3e5c0bdc488ac',
            scriptSize: 25,
            totalSize: 34
          },
          {
            value: web3.utils.toBN('79540887811'),
            pkScript: '0x76a9142591f7537994333dc2c119a88defb5b53d34495188ac',
            scriptSize: 25,
            totalSize: 34
          }
        ]
      },
      {
        raw: '0x010000000001050010b625779e40b4e8d1288e9db32a9a4026f7e98d0ee97a2fd1b43ca8882a460000000000ffffffff0010b625779e40b4e8d1288e9db32a9a4026f7e98d0ee97a2fd1b43ca8882a460100000000ffffffff0010b625779e40b4e8d1288e9db32a9a4026f7e98d0ee97a2fd1b43ca8882a460300000000fffffffffd67dda5d256393b6e5b4a1ba117c7b60ebb0ff17ff22d4743f12f3a84bcf84e0100000000fffffffffd67dda5d256393b6e5b4a1ba117c7b60ebb0ff17ff22d4743f12f3a84bcf84e0200000000ffffffff060000000000000000536a4c5063cc1853d0117afb0b709321a29ebd6bff4f0488774c3df3a7eae1f237bce099355a809b79d8e327b4844d4d5b01039c68d000fb57d906712c9403a0561a5cd7175d314dbb75bfa53cd033620f916501a60e000000000000160014f58e1a72b69982143e10e505a61f37aa368d92441302010000000000160014323d105482f5065dcd51f1bc5a213d5d723d58dda6870100000000001600140ccce8622a77f0316227cd311fb233bce31f76f6a68701000000000016001463ac4816199ba682879a2373a16fac78c51f6bdaa687010000000000160014b84a456a5a8af29af60d72b03958a9bebf76e6e502483045022100d1fb958108531911fc0ba7df04267c1842718f1d871c555f8b6ce30cc117d4ca022032099c3918c491d0af7fdded1811e2cd0e86b99458661d97ae87ded3c889382001210257d3f874b8203ed7d4fc254d67f68b67e954c19cd37b1b6a6ce7346a52b437230247304402201cbeb5d7865aa47b6a6692b89fbbcd4caad7047b71db97e42b09149594bb141402207b1eaa83ab4ebcf8b063bc401f892043c8cf346e4993bdfdc9f4f979c27ac8b001210326010652c2334417db10fddc0bb10749a3256555dd22ebe1575da9eb3aeccf530247304402205dbc9abd0df608e9548c8e5b3771f7b1f20ad170951a8c254f620ed989a7ea61022002d00d0739f33eb5afd5d7c5e07891c66939656dd024c6fbde8515d4104c052c0121020802d7c7e0e6f040644950f0712d7225cc4b755ece3e0d61568d6c8e362e375c02483045022100db6c33de82ae9e7abbdcd99265931307716112771d2e4273a7381c63e779a2ae02203376181e7e3474b6e771eea127b9ce943ef1025e9190a75304d9cf94d52ed429012103d1609fe77bb362648e9253ed09b7a560448f93fb0612a74db179ac22cc89e86302483045022100f99a02db4e116b3ff92de3cb0af8e3cf29518695fdfadac6cc9cd2104ae009d402206a1e7060874834a68aa7ad5b2ef19ea29c1f04af61aab28c589dfa8937f2287a012103dbfb01dde37e538772edf37434b4b4268f10ab8ed7e1e6a98f89e50aa1a11f2500000000',
        outputs:[
          {
            value: web3.utils.toBN('0'),
            pkScript: '0x6a4c5063cc1853d0117afb0b709321a29ebd6bff4f0488774c3df3a7eae1f237bce099355a809b79d8e327b4844d4d5b01039c68d000fb57d906712c9403a0561a5cd7175d314dbb75bfa53cd033620f916501',
            scriptSize: 83,
            totalSize: 92
          },
          {
            value: web3.utils.toBN('3750'),
            pkScript: '0x0014f58e1a72b69982143e10e505a61f37aa368d9244',
            scriptSize: 22,
            totalSize: 31
          },
          {
            value: web3.utils.toBN('66067'),
            pkScript: '0x0014323d105482f5065dcd51f1bc5a213d5d723d58dd',
            scriptSize: 22,
            totalSize: 31
          },
          {
            value: web3.utils.toBN('100262'),
            pkScript: '0x00140ccce8622a77f0316227cd311fb233bce31f76f6',
            scriptSize: 22,
            totalSize: 31
          },
          {
            value: web3.utils.toBN('100262'),
            pkScript: '0x001463ac4816199ba682879a2373a16fac78c51f6bda',
            scriptSize: 22,
            totalSize: 31
          },
          {
            value: web3.utils.toBN('100262'),
            pkScript: '0x0014b84a456a5a8af29af60d72b03958a9bebf76e6e5',
            scriptSize: 22,
            totalSize: 31
          }
        ]
      },
      {
        raw: '0x010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff1e0367352519444d47426c6f636b636861696ee2fb0ac80e02000000000000ffffffff02e338260000000000160014b23716e183ba0949c55d6cac21a3e94176eed1120000000000000000266a24aa21a9ed561c4fd92722cf983c8c24e78ef35a4634e3013695f09186bc86c6a627f21cfa0120000000000000000000000000000000000000000000000000000000000000000000000000',
        outputs:[
          {
            value: web3.utils.toBN('2504931'),
            pkScript: '0x0014b23716e183ba0949c55d6cac21a3e94176eed112',
            scriptSize: 22,
            totalSize: 31
          },
          {
            value: web3.utils.toBN('0'),
            pkScript: '0x6a24aa21a9ed561c4fd92722cf983c8c24e78ef35a4634e3013695f09186bc86c6a627f21cfa',
            scriptSize: 38,
            totalSize: 47
          }
        ]
      },
      {
        raw: '0x020000000001016bcabaaf4e28636c4c68252a019268927b79a978cc7a9c2e561d7053dd0bf73b0000000000fdffffff0296561900000000001976a9147aa8184685ca1f06f543b64a502eb3b6135d672088acf9d276e3000000001976a9145ce7908503ef69bfde873fe886133ab8dc23363188ac02473044022078607e1ca987e18ee8934b44ff8a4f0751d27a110540d99deb0a386adbf638c002200a01dc0314bef9b8c966c7a02440309596a6380e1625a7872ed616327a729bed0121029e1bb76f522491f90c542385e6dbff36b92f8984b74f24d0b99b52ea17bed09961352500',
        outputs:[
          {
            value: web3.utils.toBN('1660566'),
            pkScript: '0x76a9147aa8184685ca1f06f543b64a502eb3b6135d672088ac',
            scriptSize: 25,
            totalSize: 34
          },
          {
            value: web3.utils.toBN('3816215289'),
            pkScript: '0x76a9145ce7908503ef69bfde873fe886133ab8dc23363188ac',
            scriptSize: 25,
            totalSize: 34
          }
        ]
      },
      {
        raw: '0x020000000001014aea9ffcf9be9c98a2a3ceb391483328ff406177fdb60047886a50f33569e0540000000000fdffffff02ce095d5a120000001976a914c38cfd37c4b53ebae78de708a3d8438f6e7cc56588acbc622e00000000001976a914c3ea6613a9dcbf0a63863ec3a3b958127d597b4988ac02473044022009351dd62b2494924397a626524a5c08e16d4d214488b847e7a9cd97fa4aac2302200f5a54fff804f19edf316daaea58052a5f0c2ff3de236a45e05a43474e3a6ddf01210258f308ea046d38403d5afb201df933196b7948acead3048a0413bbaacdc42db166352500',
        outputs:[
          {
            value: web3.utils.toBN('78825458126'),
            pkScript: '0x76a914c38cfd37c4b53ebae78de708a3d8438f6e7cc56588ac',
            scriptSize: 25,
            totalSize: 34
          },
          {
            value: web3.utils.toBN('3039932'),
            pkScript: '0x76a914c3ea6613a9dcbf0a63863ec3a3b958127d597b4988ac',
            scriptSize: 25,
            totalSize: 34
          }
        ]
      },
      {
        raw: '0x010000000127d57276f1026a95b4af3b03b6aba859a001861682342af19825e8a2408ae008010000008c493046022100cd92b992d4bde3b44471677081c5ece6735d6936480ff74659ac1824d8a1958e022100b08839f167532aea10acecc9d5f7044ddd9793ef2989d090127a6e626dc7c9ce014104cac6999d6c3feaba7cdd6c62bce174339190435cffd15af7cb70c33b82027deba06e6d5441eb401c0f8f92d4ffe6038d283d2b2dd59c4384b66b7b8f038a7cf5ffffffff0200093d0000000000434104636d69f81d685f6f58054e17ac34d16db869bba8b3562aabc38c35b065158d360f087ef7bd8b0bcbd1be9a846a8ed339bf0131cdb354074244b0a9736beeb2b9ac40420f0000000000fdba0f76a9144838a081d73cf134e8ff9cfd4015406c73beceb388acacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacac00000000',
        outputs: [
          {
            value: web3.utils.toBN('4000000'),
            pkScript: '0x4104636d69f81d685f6f58054e17ac34d16db869bba8b3562aabc38c35b065158d360f087ef7bd8b0bcbd1be9a846a8ed339bf0131cdb354074244b0a9736beeb2b9ac',
            scriptSize: 67,
            totalSize: 76
          },
          {
            value: web3.utils.toBN('1000000'),
            pkScript: '0x76a9144838a081d73cf134e8ff9cfd4015406c73beceb388acacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacac',
            scriptSize: 4026,
            totalSize: 4037
          }
        ]
      }
    ];

    let outputs;
    for (let tx of transactions) {
      outputs = await btcUtils.getOutputs(tx.raw)
      expect(outputs.length).to.eq(tx.outputs.length)
      for (let i = 0;  i < outputs.length; i++) {
        expect(outputs[i].value).to.eq(tx.outputs[i].value.toString());
        expect(outputs[i].pkScript).to.eq(tx.outputs[i].pkScript);
        expect(outputs[i].scriptSize).to.eq(tx.outputs[i].scriptSize.toString());
        expect(outputs[i].totalSize).to.eq(tx.outputs[i].totalSize.toString());
      }
    }
  })

  it("Should verify depositAddress for given quote", async () => {
    const tests = [
      {
        quote: {
          fedBtcAddress: bs58check.decode("2N5muMepJizJE1gR7FbHJU6CD18V3BpNF9p").slice(1),
          lbcAddress: instance.address,
          liquidityProviderRskAddress: "0x9D93929A9099be4355fC2389FbF253982F9dF47c",
          btcRefundAddress:  bs58check.decode("mxqk28jvEtvjxRN8k7W9hFEJfWz5VcUgHW"),
          rskRefundAddress: "0xa2193A393aa0c94A4d52893496F02B56C61c36A1",
          liquidityProviderBtcAddress: bs58check.decode("mnYcQxCZBbmLzNfE9BhV7E8E2u7amdz5y6"),
          callFee: BigInt("1000000000000000"),
          penaltyFee: 1000000,
          contractAddress: "0xa2193A393aa0c94A4d52893496F02B56C61c36A1",
          data: '0x',
          gasLimit: 46000,
          nonce: BigInt("3426962016206607167"),
          value: BigInt("600000000000000000"),
          agreementTimestamp: 1691772110,
          timeForDeposit: 3600,
          callTime: 7200,
          depositConfirmations: 10,
          callOnRegister: false,
          productFeeAmount: BigInt("6000000000000000"),
          gasFee: BigInt("3000000000000000")
        },
        address: '2N54HuutZf7Xkmv85wCtBkQg5nCC3k432rf'
      },
      {
        quote: {
          fedBtcAddress: bs58check.decode("2N5muMepJizJE1gR7FbHJU6CD18V3BpNF9p").slice(1),
          lbcAddress: instance.address,
          liquidityProviderRskAddress: "0x9D93929A9099be4355fC2389FbF253982F9dF47c",
          btcRefundAddress:  bs58check.decode("mi5vEG69RGhi3RKsn7bWco5xnafZvsXvrF"),
          rskRefundAddress: "0x69b3886457c0e0654d9829d29a6156f49236235c",
          liquidityProviderBtcAddress: bs58check.decode("mnYcQxCZBbmLzNfE9BhV7E8E2u7amdz5y6"),
          callFee: BigInt("1000000000000000"),
          penaltyFee: 1000000,
          contractAddress: "0x7221249458b5e2055b33069a27836985a3822c99",
          data: '0x',
          gasLimit: 46000,
          nonce: BigInt("7363369648470809209"),
          value: BigInt("700000000000000000"),
          agreementTimestamp: 1691873604,
          timeForDeposit: 3600,
          callTime: 7200,
          depositConfirmations: 10,
          callOnRegister: false,
          productFeeAmount: BigInt("7000000000000000"),
          gasFee: BigInt("4000000000000000")
        },
        address: '2NARRvPtz2ch1KozGfZg6FahLSVVaSG2fQr'
      },
      {
        quote: {
          fedBtcAddress: bs58check.decode("2N5muMepJizJE1gR7FbHJU6CD18V3BpNF9p").slice(1),
          lbcAddress: instance.address,
          liquidityProviderRskAddress: "0x9D93929A9099be4355fC2389FbF253982F9dF47c",
          btcRefundAddress:  bs58check.decode("mjSE41mAMwqdYsXiibUgyWe4oESoCygf96"),
          rskRefundAddress: "0xc67319ce23965591947a93884356252477330456",
          liquidityProviderBtcAddress: bs58check.decode("mnYcQxCZBbmLzNfE9BhV7E8E2u7amdz5y6"),
          callFee: BigInt("1000000000000000"),
          penaltyFee: 1000000,
          contractAddress: "0x48c8396629c550203e183350c9074a2b42e83d1a",
          data: '0x',
          gasLimit: 46000,
          nonce: BigInt("8681289575209299775"),
          value: BigInt("800000000000000000"),
          agreementTimestamp: 1691874253,
          timeForDeposit: 3600,
          callTime: 7200,
          depositConfirmations: 10,
          callOnRegister: false,
          productFeeAmount: BigInt("8000000000000000"),
          gasFee: BigInt("5000000000000000")
        },
        address: '2Mwfc2XRxm64dDbNowHUFj2pZ4owePhNFyQ'
      }
    ]

    for (const test of tests) {
      const decoded = web3.utils.bytesToHex(bs58.decode(test.address))
      expect(await instance.validatePeginDepositAddress(test.quote, decoded)).to.be.true
    }
  });

  it('Should throw error in hashQuote if summing quote agreementTimestamp and timeForDeposit cause overflow', async () => {
    const quote = utils.getTestQuote(
      instance.address,
      accounts[1],
      "0x00",
      liquidityProviderRskAddress,
      accounts[2],
      web3.utils.toBN(1)
    );
    quote.agreementTime = 4294967294;
    quote.timeForDeposit = 4294967294;
    await truffleAssertions.reverts(
      instance.hashQuote(utils.asArray(quote)),
      "LBC071"
    );
  })

  it('Should update the liquidity provider information correctly', async () => {
    const providerAddress = accounts[9]
    let provider = await instance.getProviders().then(result => result.at(0))

    const initialState = {
      id: provider.id,
      provider: provider.provider,
      name: provider.name,
      apiBaseUrl: provider.apiBaseUrl,
      status: provider.status,
      providerType: provider.providerType
    }

    const newName = 'modified name'
    const newApiBaseUrl = 'https://modified.com'

    const tx = await instance.updateProvider(newName, newApiBaseUrl, { from: providerAddress })
    truffleAssertions.eventEmitted(tx, "ProviderUpdate", {
      providerAddress: providerAddress,
      name: newName,
      url: newApiBaseUrl
    });

    provider = await instance.getProviders().then(result => result.at(0))
    const finalState = {
      id: provider.id,
      provider: provider.provider,
      name: provider.name,
      apiBaseUrl: provider.apiBaseUrl,
      status: provider.status,
      providerType: provider.providerType
    }

    expect(initialState.id).to.eq(finalState.id)
    expect(initialState.provider).to.eq(finalState.provider)
    expect(initialState.status).to.eq(finalState.status)
    expect(initialState.providerType).to.eq(finalState.providerType)
    expect(initialState.name).to.not.eq(finalState.name)
    expect(initialState.apiBaseUrl).to.not.eq(finalState.apiBaseUrl)
    expect(finalState.name).to.eq(newName)
    expect(finalState.apiBaseUrl).to.eq(newApiBaseUrl)
  })

  it('Should fail if unregistered provider updates his information', async () => {
    const providerAddress = accounts[8]
    const newName = 'not-existing name'
    const newApiBaseUrl = 'https://not-existing.com'
    const tx = instance.updateProvider(newName, newApiBaseUrl, { from: providerAddress })
    await truffleAssertions.reverts(tx, "LBC001");
  })

  it('Should fail if provider makes update with invalid information', async () => {
    const providerAddress = accounts[9]
    const newName = 'any name'
    const newApiBaseUrl = 'https://any.com'
    const wrongName = instance.updateProvider('', newApiBaseUrl, { from: providerAddress })
    await truffleAssertions.reverts(wrongName, "LBC076");
    const wrongUrl = instance.updateProvider(newName, '', { from: providerAddress })
    await truffleAssertions.reverts(wrongUrl, "LBC076");
  })

  describe("Function getProviders should", () => {
    it("list enabled and not resigned providers only", async () => {
      await instance.setProviderStatus(7, false);
      /**
       * Providers statuses per account:
       * 0 - disabled
       * 1 - active
       * 2 - active
       * 3 - resigned and disabled
       * 4 - active
       * 5 - resigned but active
       * 6 - resigned but active
       * 7 - resigned but active
       * 8 - Not a provider
       * 9 - active
       */
      const result = await instance.getProviders();
      expect(result.length).to.eq(4);
      expect(utils.parseLiquidityProvider(result[0])).to.deep.equal({
        id: 2,
        provider: accounts[9],
        name: "modified name",
        apiBaseUrl: "https://modified.com",
        status: true,
        providerType: "both"
      });
      expect(utils.parseLiquidityProvider(result[1])).to.deep.equal({
        id: 3,
        provider: accounts[4],
        name: "First contract",
        apiBaseUrl: "http://localhost/api",
        status: true,
        providerType: "both"
      });
      expect(utils.parseLiquidityProvider(result[2])).to.deep.equal({
        id: 4,
        provider: accounts[1],
        name: "First contract",
        apiBaseUrl: "http://localhost/api",
        status: true,
        providerType: "both"
      });
      expect(utils.parseLiquidityProvider(result[3])).to.deep.equal({
        id: 5,
        provider: accounts[2],
        name: "Second contract",
        apiBaseUrl: "http://localhost/api",
        status: true,
        providerType: "both"
      });
    })
  });
});
