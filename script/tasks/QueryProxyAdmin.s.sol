// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";
import {ProxyReader} from "../helpers/ProxyReader.sol";

/**
 * @title QueryProxyAdmin
 * @notice Read-only script: reads the ERC-1967 proxy admin address for a given proxy contract
 * @dev Uses storage slot `eip1967.proxy.admin` (EIP-1967), matching OpenZeppelin `TransparentUpgradeableProxy`
 *      and `ERC1967Proxy`. This is the address that controls upgrades (often a `ProxyAdmin` contract).
 *
 * ## Usage (address argument)
 *   forge script script/tasks/QueryProxyAdmin.s.sol:QueryProxyAdmin \
 *     --sig "readProxyAdmin(address)" <proxy-address> \
 *     --rpc-url <rpc-url>
 *
 * ## Usage (environment)
 *   PROXY_ADDRESS=<proxy-address> forge script script/tasks/QueryProxyAdmin.s.sol:QueryProxyAdmin \
 *     --sig "readProxyAdminFromEnv()" \
 *     --rpc-url <rpc-url>
 */

interface IOwnable {
    function owner() external view returns (address);
}

contract QueryProxyAdmin is Script {
    function readProxyAdminFromEnv() external view {
        address proxy = _proxyFromEnv();
        readProxyAdmin(proxy);
    }

    function readProxyAdmin(address proxy) public view {
        if (proxy == address(0)) {
            revert("proxy address is zero");
        }

        address admin = ProxyReader.readAdmin(vm, proxy);

        console.log("\n=== ERC-1967 PROXY ADMIN ===\n");
        console.log("Proxy:", proxy);
        console.log("Admin (from storage slot):", admin);
        if (admin == address(0)) {
            console.log(
                "Note: admin slot is zero - not an ERC-1967 proxy or uninitialized."
            );
            return;
        }

        if (admin.code.length > 0) {
            try IOwnable(admin).owner() returns (address own) {
                console.log("Admin owner:", own);
            } catch {}
        }
    }

    function _proxyFromEnv() private view returns (address) {
        try vm.envAddress("PROXY_ADDRESS") returns (address a) {
            if (a != address(0)) {
                return a;
            }
        } catch {}
        revert("Set PROXY_ADDRESS to the proxy contract address.");
    }
}
