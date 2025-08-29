import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployDiscoveryWithProvidersFixture } from "./fixtures";
import { ProviderType } from "../utils/constants";

describe("FlyoverDiscovery operational checks", () => {
  it("isOperational returns true only for providers with peg-in collateral", async () => {
    const { discovery, pegInLp, fullLp, pegOutLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );

    expect(
      await discovery.isOperational(ProviderType.PegIn, pegInLp.address)
    ).to.equal(true);
    expect(
      await discovery.isOperational(ProviderType.PegIn, fullLp.address)
    ).to.equal(true);
    expect(
      await discovery.isOperational(ProviderType.PegIn, pegOutLp.address)
    ).to.equal(false);
  });
});
