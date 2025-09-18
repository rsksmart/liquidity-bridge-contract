import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { deployDiscoveryWithProvidersFixture } from "./fixtures";
import { ProviderType } from "../utils/constants";

describe("FlyoverDiscovery getters", () => {
  it("lists registered providers with correct fields", async () => {
    const { discovery, pegInLp, pegOutLp, fullLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );

    const providers = await discovery.getProviders();
    expect(providers.length).to.equal(3);

    const [p1, p2, p3] = providers;

    expect(p1.id).to.equal(1n);
    expect(p1.providerAddress).to.equal(pegInLp.address);
    expect(p1.name).to.equal("Pegin Provider");
    expect(p1.apiBaseUrl).to.equal("lp1.com");
    expect(p1.status).to.equal(true);
    expect(p1.providerType).to.equal(ProviderType.PegIn);

    expect(p2.id).to.equal(2n);
    expect(p2.providerAddress).to.equal(pegOutLp.address);
    expect(p2.name).to.equal("PegOut Provider");
    expect(p2.apiBaseUrl).to.equal("lp2.com");
    expect(p2.status).to.equal(true);
    expect(p2.providerType).to.equal(ProviderType.PegOut);

    expect(p3.id).to.equal(3n);
    expect(p3.providerAddress).to.equal(fullLp.address);
    expect(p3.name).to.equal("Full Provider");
    expect(p3.apiBaseUrl).to.equal("lp3.com");
    expect(p3.status).to.equal(true);
    expect(p3.providerType).to.equal(ProviderType.Both);
  });

  it("gets a provider by address", async () => {
    const { discovery, pegOutLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const provider = await discovery.getProvider(pegOutLp.address);
    expect(provider.id).to.equal(2n);
    expect(provider.providerAddress).to.equal(pegOutLp.address);
    expect(provider.name).to.equal("PegOut Provider");
    expect(provider.apiBaseUrl).to.equal("lp2.com");
    expect(provider.status).to.equal(true);
    expect(provider.providerType).to.equal(ProviderType.PegOut);
  });

  it("reverts when getting a non-existing provider", async () => {
    const { discovery } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const nonLp = ethers.Wallet.createRandom().address;
    await expect(discovery.getProvider(nonLp)).to.be.revertedWithCustomError(
      discovery,
      "ProviderNotRegistered"
    );
  });
});
