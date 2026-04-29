import { REGISTER_LP_PARAMS, RegisterLpParams } from "./utils/constants";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployLbcWithProvidersFixture } from "./utils/fixtures";

describe("LiquidityBridgeContractV2 provider discovery should", () => {
  it("list registered providers", async () => {
    const { lbc, liquidityProviders } = await loadFixture(
      deployLbcWithProvidersFixture
    );
    const providerList = await lbc.getProviders();
    expect(providerList.length).to.be.eq(3);
    providerList.forEach((p, i) => {
      expect(p.id).to.be.eq(i + 1);
      expect(p.provider).to.be.eq(liquidityProviders[i].signer.address);
      expect(p.name).to.be.eq(liquidityProviders[i].registerParams[0]);
      expect(p.apiBaseUrl).to.be.eq(liquidityProviders[i].registerParams[1]);
      expect(p.status).to.be.eq(liquidityProviders[i].registerParams[2]);
      expect(p.providerType).to.be.eq(liquidityProviders[i].registerParams[3]);
    });
  });

  it("get the last provider id", async () => {
    const { lbc, liquidityProviders } = await loadFixture(
      deployLbcWithProvidersFixture
    );
    const lastProviderId = await lbc.getProviderIds();
    expect(lastProviderId).to.be.eq(liquidityProviders.length);
  });

  it("allow a provider to disable by itself", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const lp = fixtureResult.liquidityProviders[1];
    let lbc = fixtureResult.lbc;
    lbc = lbc.connect(lp.signer);
    await lbc.setProviderStatus(2, false);
    const provider = await lbc.getProvider(lp.signer.address);
    expect(provider.status).to.be.eq(false);
  });

  it("fail if provider does not exist", async () => {
    const { lbc, liquidityProviders, accounts } = await loadFixture(
      deployLbcWithProvidersFixture
    );
    const notLpSigner = accounts[0];
    expect(
      liquidityProviders.some((lp) => lp.signer.address === notLpSigner.address)
    ).to.be.eq(false);
    await expect(lbc.getProvider(notLpSigner.address)).to.be.revertedWith(
      "LBC001"
    );
  });

  it("return correct state of a provider", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const [lp1, lp2] = fixtureResult.liquidityProviders;
    let lbc = fixtureResult.lbc;
    lbc = lbc.connect(lp1.signer);
    const tx = await lbc.setProviderStatus(1, false);
    await tx.wait();
    let provider = await lbc.getProvider(lp1.signer.address);
    expect(provider.status).to.be.eq(false);
    expect(provider.name).to.be.equal("First LP");
    expect(provider.apiBaseUrl).to.be.equal("http://localhost/api1");
    expect(provider.provider).to.be.equal(lp1.signer.address);
    expect(provider.providerType).to.be.equal("both");
    provider = await lbc.getProvider(lp2.signer.address);
    expect(provider.status).to.be.eq(true);
    expect(provider.name).to.be.equal("Second LP");
    expect(provider.apiBaseUrl).to.be.equal("http://localhost/api2");
    expect(provider.provider).to.be.equal(lp2.signer.address);
    expect(provider.providerType).to.be.equal("pegin");
  });

  it("allow a provider to enable by itself", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const lp = fixtureResult.liquidityProviders[1];
    let lbc = fixtureResult.lbc;
    lbc = lbc.connect(lp.signer);

    await lbc.setProviderStatus(2, false);
    let provider = await lbc.getProvider(lp.signer.address);
    expect(provider.status).to.be.eq(false);

    await lbc.setProviderStatus(2, true);
    provider = await lbc.getProvider(lp.signer.address);
    expect(provider.status).to.be.eq(true);
  });
  it("disable and enable provider as LBC owner", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, lbcOwner } = fixtureResult;
    let lbc = fixtureResult.lbc;
    const lp = liquidityProviders[1];
    lbc = lbc.connect(lbcOwner);

    await lbc.setProviderStatus(2, false);
    let provider = await lbc.getProvider(lp.signer.address);
    expect(provider.status).to.be.eq(false);

    await lbc.setProviderStatus(2, true);
    provider = await lbc.getProvider(lp.signer.address);
    expect(provider.status).to.be.eq(true);
  });

  it("fail disabling provider as non owners", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const lp = fixtureResult.liquidityProviders[0]; // the id of this provider is 1
    let lbc = fixtureResult.lbc;
    lbc = lbc.connect(lp.signer);
    await expect(lbc.setProviderStatus(2, false)).to.be.revertedWith("LBC005");
  });

  it("update the liquidity provider information correctly", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders } = fixtureResult;
    let lbc = fixtureResult.lbc;

    const providerIndex = 1;
    const providerSigner = liquidityProviders[providerIndex].signer;
    let provider = await lbc
      .getProviders()
      .then((result) => result[providerIndex]);

    const initialState = {
      id: provider.id,
      provider: provider.provider,
      name: provider.name,
      apiBaseUrl: provider.apiBaseUrl,
      status: provider.status,
      providerType: provider.providerType,
    };

    const newName = "modified name";
    const newApiBaseUrl = "https://modified.com";

    lbc = lbc.connect(providerSigner);
    const tx = await lbc.updateProvider(newName, newApiBaseUrl);
    await expect(tx)
      .to.emit(lbc, "ProviderUpdate")
      .withArgs(providerSigner.address, newName, newApiBaseUrl);

    provider = await lbc.getProviders().then((result) => result[providerIndex]);
    const finalState = {
      id: provider.id,
      provider: provider.provider,
      name: provider.name,
      apiBaseUrl: provider.apiBaseUrl,
      status: provider.status,
      providerType: provider.providerType,
    };

    expect(initialState.id).to.be.eq(finalState.id);
    expect(initialState.provider).to.be.eq(finalState.provider);
    expect(initialState.status).to.be.eq(finalState.status);
    expect(initialState.providerType).to.be.eq(finalState.providerType);
    expect(initialState.name).to.not.be.eq(finalState.name);
    expect(initialState.apiBaseUrl).to.not.be.eq(finalState.apiBaseUrl);
    expect(finalState.name).to.be.eq(newName);
    expect(finalState.apiBaseUrl).to.be.eq(newApiBaseUrl);
  });

  it("fail if unregistered provider updates his information", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { accounts } = fixtureResult;
    const provider = accounts[5];
    const lbc = fixtureResult.lbc.connect(provider);
    const newName = "not-existing name";
    const newApiBaseUrl = "https://not-existing.com";
    const tx = lbc.updateProvider(newName, newApiBaseUrl);
    await expect(tx).to.be.revertedWith("LBC001");
  });

  it("fail if provider makes update with invalid information", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders } = fixtureResult;
    const provider = liquidityProviders[2];
    const lbc = fixtureResult.lbc.connect(provider.signer);
    const newName = "any name";
    const newApiBaseUrl = "https://any.com";
    const wrongName = lbc.updateProvider("", newApiBaseUrl);
    await expect(wrongName).to.be.revertedWith("LBC076");
    const wrongUrl = lbc.updateProvider(newName, "");
    await expect(wrongUrl).to.be.revertedWith("LBC076");
  });

  it("list enabled and not resigned providers only", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, accounts } = fixtureResult;
    let lbc = fixtureResult.lbc;
    /**
     * Target provider statuses per account:
     * 0 - lbc owner (not a provider)
     *
     * accounts array
     * 1 - active (LP 4)
     * 2 - not a provider
     * 3 - resigned and disabled (LP 5)
     * 4 - disabled (LP 6)
     * 5 - active (LP 7)
     * 6 - resigned but active (LP 8)
     *
     * LPs array
     * 7 - active (LP 1)
     * 8 - disabled (LP 2)
     * 9 - active (LP 3)
     */

    // Prepare the expected statuses
    lbc = lbc.connect(liquidityProviders[1].signer);
    await lbc.setProviderStatus(2, false);

    const newLps = [0, 2, 3, 4, 5].map((i) => ({
      signer: accounts[i],
      accountIdx: i,
    }));
    for (const lp of newLps) {
      lbc = lbc.connect(lp.signer);
      const params: RegisterLpParams = [...REGISTER_LP_PARAMS];
      params[0] = `LP account ${lp.accountIdx.toString()}`;
      // eslint-disable-next-line @typescript-eslint/no-base-to-string
      params[1] = `${params[1].toString()}-account${lp.accountIdx.toString()}`;
      const registerTx = await lbc.register(...params);
      await expect(registerTx).to.emit(lbc, "Register");
    }

    lbc = lbc.connect(newLps[1].signer);
    await lbc.setProviderStatus(5, false).then((tx) => tx.wait());
    await lbc.resign().then((tx) => tx.wait());

    lbc = lbc.connect(newLps[2].signer);
    await lbc.setProviderStatus(6, false).then((tx) => tx.wait());

    lbc = lbc.connect(newLps[4].signer);
    await lbc.resign().then((tx) => tx.wait());

    lbc = lbc.connect(accounts[1]);
    const result = await lbc.getProviders();
    expect(result.length).to.be.eq(4);
    expect(result[0]).to.be.deep.equal([
      1n,
      liquidityProviders[0].signer.address,
      "First LP",
      "http://localhost/api1",
      true,
      "both",
    ]);
    expect(result[1]).to.be.deep.equal([
      3n,
      liquidityProviders[2].signer.address,
      "Third LP",
      "http://localhost/api3",
      true,
      "pegout",
    ]);
    expect(result[2]).to.be.deep.equal([
      4n,
      accounts[0].address,
      "LP account 0",
      "http://localhost/api-account0",
      true,
      "both",
    ]);
    expect(result[3]).to.be.deep.equal([
      7n,
      accounts[4].address,
      "LP account 4",
      "http://localhost/api-account4",
      true,
      "both",
    ]);
  });
});
