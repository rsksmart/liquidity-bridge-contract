import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployDiscoveryWithProvidersFixture } from "./fixtures";
import { ProviderType } from "../utils/constants";

describe("FlyoverDiscovery operational checks", () => {
  it("isOperational returns true only for providers with sufficient collateral for their type", async () => {
    const { discovery, pegInLp, fullLp, pegOutLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );

    // Test PegIn operations
    expect(
      await discovery.isOperational(ProviderType.PegIn, pegInLp.address)
    ).to.equal(true);
    expect(
      await discovery.isOperational(ProviderType.PegIn, fullLp.address)
    ).to.equal(true);
    expect(
      await discovery.isOperational(ProviderType.PegIn, pegOutLp.address)
    ).to.equal(false);

    // Test PegOut operations
    expect(
      await discovery.isOperational(ProviderType.PegOut, pegInLp.address)
    ).to.equal(false);
    expect(
      await discovery.isOperational(ProviderType.PegOut, fullLp.address)
    ).to.equal(true);
    expect(
      await discovery.isOperational(ProviderType.PegOut, pegOutLp.address)
    ).to.equal(true);

    // Test Both operations (requires sufficient collateral for both PegIn AND PegOut)
    expect(
      await discovery.isOperational(ProviderType.Both, pegInLp.address)
    ).to.equal(false); // Only has PegIn collateral
    expect(
      await discovery.isOperational(ProviderType.Both, pegOutLp.address)
    ).to.equal(false); // Only has PegOut collateral
    expect(
      await discovery.isOperational(ProviderType.Both, fullLp.address)
    ).to.equal(true); // Has both PegIn and PegOut collateral
  });
});
