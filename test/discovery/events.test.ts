import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import {
  deployDiscoveryFixture,
  deployDiscoveryWithProvidersFixture,
} from "./fixtures";
import { ProviderType } from "../utils/constants";

describe("FlyoverDiscovery events", () => {
  it("emits Register with id, sender, and amount", async () => {
    const { discovery, signers, MIN_COLLATERAL } = await loadFixture(
      deployDiscoveryFixture
    );
    const lp = signers.at(-1)!;
    await expect(
      discovery
        .connect(lp)
        .register("N", "U", true, ProviderType.PegIn, { value: MIN_COLLATERAL })
    )
      .to.emit(discovery, "Register")
      .withArgs(1n, lp.address, MIN_COLLATERAL);
  });

  it("emits ProviderStatusSet when toggling status", async () => {
    const { discovery, pegOutLp } = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    await expect(discovery.connect(pegOutLp).setProviderStatus(2, false))
      .to.emit(discovery, "ProviderStatusSet")
      .withArgs(2n, false);
  });
});
