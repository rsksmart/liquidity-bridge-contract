const PegoutContract = artifacts.require("PegoutContract");
const PeginContract = artifacts.require("PeginContract");
const LiquidityProviderContract = artifacts.require("LiquidityProviderContract");
const utils = require("../test/utils/index");
const truffleAssert = require('truffle-assertions');


const assertAccessControlBlock = (e, msg = "AccessControl") => {
    expect(e.reason?.includes(msg) || e.message?.includes(msg)).to.be.true;
    throw e;
}

contract("LiquidityProviderContract", async () => {
    let instance;
    before(async () => {
        const proxy = await LiquidityProviderContract.deployed();
        instance = await LiquidityProviderContract.at(proxy.address);
    });
    it("should protect isRegistered from external calls", async () => {
        await truffleAssert.reverts(instance.isRegistered("0x0000000000000000000000000000000000000000").catch(assertAccessControlBlock));
    });
    it("should protect isRegisteredForPegout from external calls", async () => {
        await truffleAssert.reverts(instance.isRegisteredForPegout("0x0000000000000000000000000000000000000000").catch(assertAccessControlBlock));
    });
    it("should protect setProviderStatus from external calls", async () => {
        await truffleAssert.reverts(
            instance.setProviderStatus("0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000", true)
                .catch(assertAccessControlBlock)
        );
    });
    it("should protect register from external calls", async () => {
        await truffleAssert.reverts(
            instance.register("0x0000000000000000000000000000000000000000", "", 1, 1, 1, 1, "", true, "").catch(assertAccessControlBlock)
        );
    });
    it("should protect deposit from external calls", async () => {
        await truffleAssert.reverts(
            instance.deposit("0x0000000000000000000000000000000000000000").catch(assertAccessControlBlock)
        );
    });
    it("should protect addCollateral from external calls", async () => {
        await truffleAssert.reverts(
            instance.addCollateral("0x0000000000000000000000000000000000000000").catch(assertAccessControlBlock)
        );
    });
    it("should protect addPegoutCollateral from external calls", async () => {
        await truffleAssert.reverts(
            instance.addPegoutCollateral("0x0000000000000000000000000000000000000000").catch(assertAccessControlBlock)
        );
    });
    it("should protect withdraw from external calls", async () => {
        await truffleAssert.reverts(
            instance.withdraw("0x0000000000000000000000000000000000000000", 1).catch(assertAccessControlBlock)
        );
    });
    it("should protect withdrawCollateral from external calls", async () => {
        await truffleAssert.reverts(
            instance.withdrawCollateral("0x0000000000000000000000000000000000000000").catch(assertAccessControlBlock)
        );
    });
    it("should protect withdrawPegoutCollateral from external calls", async () => {
        await truffleAssert.reverts(
            instance.withdrawPegoutCollateral("0x0000000000000000000000000000000000000000").catch(assertAccessControlBlock)
        );
    });
    it("should protect resign from external calls", async () => {
        await truffleAssert.reverts(
            instance.resign("0x0000000000000000000000000000000000000000").catch(assertAccessControlBlock)
        );
    });
    it("should protect getProviders from external calls", async () => {
        await truffleAssert.reverts(
            instance.getProviders([]).catch(assertAccessControlBlock)
        );
    });
    it("should protect increaseBalance from external calls", async () => {
        await truffleAssert.reverts(
            instance.increaseBalance("0x0000000000000000000000000000000000000000", 1).catch(assertAccessControlBlock)
        );
    });
    it("should protect decreaseBalance from external calls", async () => {
        await truffleAssert.reverts(
            instance.decreaseBalance("0x0000000000000000000000000000000000000000", 1).catch(assertAccessControlBlock)
        );
    });
    it("should protect useBalance from external calls", async () => {
        await truffleAssert.reverts(
            instance.useBalance(1).catch(assertAccessControlBlock)
        );
    });
    it("should protect penalizeForPegin from external calls", async () => {
        const quote = utils.getTestQuote(
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x00",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            web3.utils.toBN(1)
        );
        await truffleAssert.reverts(
            instance.penalizeForPegin(utils.asArray(quote), "0x00").catch(assertAccessControlBlock)
        );
    });
    it("should protect penalizeForPegout from external calls", async () => {
        const quote = utils.getTestPegOutQuote(
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            1
        );
        await truffleAssert.reverts(
            instance.penalizeForPegout(quote, "0x00").catch(assertAccessControlBlock)
        );
    });
});
contract("PeginContract", async (accounts) => {
    let instance;
    let quote;
    before(async () => {
        const proxy = await PeginContract.deployed();
        instance = await PeginContract.at(proxy.address);
        quote = utils.getTestQuote(
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x00",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            web3.utils.toBN(1)
        );
    });
    it("should protect hashQuote from external calls", async () => {
        await truffleAssert.reverts(instance.hashQuote(utils.asArray(quote)).catch(assertAccessControlBlock));
    });
    it("should protect callForUser from external calls", async () => {
        await truffleAssert.reverts(
            instance.callForUser("0x0000000000000000000000000000000000000000", utils.asArray(quote)).catch(assertAccessControlBlock)
        );
    });
    it("should protect registerPegIn from external calls", async () => {
        await truffleAssert.reverts(
            instance.registerPegIn("0x0000000000000000000000000000000000000000", utils.asArray(quote), [], [], [], 1).catch(assertAccessControlBlock)
        );
    });
    it("should protect setProviderInterfaceAddress from non owner calls", async () => {
        await truffleAssert.reverts(
            instance.setProviderInterfaceAddress("0x0000000000000000000000000000000000000000", { from: accounts[5] })
                .catch(e => assertAccessControlBlock(e, "LBC072"))
        );
    });
});

contract("PegoutContract", async (accounts) => {
    let instance;
    let quote;
    before(async () => {
        const proxy = await PegoutContract.deployed();
        instance = await PegoutContract.at(proxy.address);
        quote = utils.getTestPegOutQuote(
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            1
        );
    });

    it("should protect refundPegout from external calls", async () => {
        await truffleAssert.reverts(instance.refundPegOut("0x0000000000000000000000000000000000000000", "0x00", [], "0x00", 1, []).catch(assertAccessControlBlock));
    });
    it("should protect depositPegout from external calls", async () => {
        await truffleAssert.reverts(instance.depositPegout("0x0000000000000000000000000000000000000000", quote, []).catch(assertAccessControlBlock));
    });
    it("should protect refundUserPegOut from external calls", async () => {
        await truffleAssert.reverts(instance.refundUserPegOut("0x00").catch(assertAccessControlBlock));
    });
    it("should protect hashPegoutQuote from external calls", async () => {
        await truffleAssert.reverts(instance.hashPegoutQuote(quote).catch(assertAccessControlBlock));
    });
    it("should protect setProviderInterfaceAddress from non owner calls", async () => {
        await truffleAssert.reverts(
            instance.setProviderInterfaceAddress("0x0000000000000000000000000000000000000000", { from: accounts[5] })
                .catch(e => assertAccessControlBlock(e, "LBC072"))
        );
    });
});