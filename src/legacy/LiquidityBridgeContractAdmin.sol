// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract LiquidityBridgeContractAdmin is ProxyAdmin {
    constructor() ProxyAdmin(msg.sender) {}
}
