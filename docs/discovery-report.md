# Discovery executions with different number of LPs

## One liquidity provider

## Methods

| **Symbol** | **Meaning**                                                                              |
| :--------: | :--------------------------------------------------------------------------------------- |
|   **◯**    | Execution gas for this method does not include intrinsic gas overhead                    |
|   **△**    | Cost was non-zero but below the precision setting for the currency display (see options) |

|                                       |    Min |    Max |     Avg | Calls | usd avg |
| :------------------------------------ | -----: | -----: | ------: | ----: | ------: |
| **CollateralManagementContract**      |        |        |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |      - |      - |   5,382 |     1 |       - |
|        *grantRole*                    |      - |      - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |        |        |         |       |         |
|     **◯** _getProvider_               |      - |      - |  21,368 |     1 |       - |
|     **◯** _getProviders_              |      - |      - |  43,958 |     1 |       - |
|     **◯** _isOperational_             | 38,789 | 41,176 |  39,600 |     3 |       - |
|        *register*                     |      - |      - | 253,280 |     2 |       - |
| **FlyoverDiscoveryFull**              |        |        |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |      - |      - |   5,426 |     1 |       - |
|     **◯** _getProvider_               |      - |      - |  21,561 |     1 |       - |
|     **◯** _getProviders_              |      - |      - |  31,485 |     1 |       - |
|        *grantRole*                    |      - |      - |  56,855 |     2 |       - |
|     **◯** _isOperational_             | 27,853 | 30,242 |  28,666 |     3 |       - |
|        *register*                     |      - |      - | 218,341 |     2 |       - |
| **LiquidityBridgeContractV2**         |        |        |         |       |         |
|     **◯** _getProvider_               |      - |      - |  24,376 |     1 |       - |
|     **◯** _getProviders_              |      - |      - |  31,679 |     1 |       - |
|     **◯** _isOperational_             |      - |      - |  12,518 |     1 |       - |
|     **◯** _isOperationalForPegout_    |      - |      - |  12,540 |     1 |       - |
|        *register*                     |      - |      - | 239,737 |     2 |       - |
| **ProxyAdmin**                        |        |        |         |       |         |
|     **◯** _owner_                     |      - |      - |      96 |     4 |       - |
|     **◯** _UPGRADE_INTERFACE_VERSION_ |      - |      - |     567 |     1 |       - |
|        *upgradeAndCall*               |      - |      - |  37,821 |     1 |       - |

## Deployments

|                                  | Min | Max |       Avg | Block % | usd avg |
| :------------------------------- | --: | --: | --------: | ------: | ------: |
| **BridgeMock**                   |   - |   - | 1,010,222 |   3.4 % |       - |
| **BtcUtils**                     |   - |   - | 2,027,187 |   6.8 % |       - |
| **CollateralManagementContract** |   - |   - | 1,579,208 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,618,189 |   5.4 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,554,548 |   8.5 % |       - |
| **LiquidityBridgeContract**      |   - |   - | 5,292,711 |  17.6 % |       - |
| **LiquidityBridgeContractV2**    |   - |   - | 5,360,117 |  17.9 % |       - |
| **Quotes**                       |   - |   - |   634,029 |   2.1 % |       - |
| **QuotesV2**                     |   - |   - |   662,913 |   2.2 % |       - |
| **SignatureValidatorMock**       |   - |   - |   138,348 |   0.5 % |       - |

## Solidity and Network Config

| **Settings**        | **Value**  |
| ------------------- | ---------- |
| Solidity: version   | 0.8.25     |
| Solidity: optimized | true       |
| Solidity: runs      | 1          |
| Solidity: viaIR     | false      |
| Block Limit         | 30,000,000 |
| Gas Price           | -          |
| Token Price         | -          |
| Network             | ETHEREUM   |
| Toolchain           | hardhat    |

## Two liquidity providers

## Methods

| **Symbol** | **Meaning**                                                                              |
| :--------: | :--------------------------------------------------------------------------------------- |
|   **◯**    | Execution gas for this method does not include intrinsic gas overhead                    |
|   **△**    | Cost was non-zero but below the precision setting for the currency display (see options) |

|                                       |     Min |     Max |     Avg | Calls | usd avg |
| :------------------------------------ | ------: | ------: | ------: | ----: | ------: |
| **CollateralManagementContract**      |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  21,368 |  23,990 |  22,679 |     2 |       - |
|     **◯** _getProviders_              |       - |       - |  68,430 |     1 |       - |
|     **◯** _isOperational_             |  21,307 |  41,263 |  34,170 |     6 |       - |
|        *register*                     | 205,571 | 253,280 | 229,426 |     4 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,426 |     1 |       - |
|     **◯** _getProvider_               |  21,561 |  24,180 |  22,871 |     2 |       - |
|     **◯** _getProviders_              |       - |       - |  51,593 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,844 |  30,306 |  23,389 |     6 |       - |
|        *register*                     | 179,155 | 218,341 | 198,748 |     4 |       - |
| **LiquidityBridgeContractV2**         |         |         |         |       |         |
|     **◯** _getProvider_               |  24,376 |  26,825 |  25,601 |     2 |       - |
|     **◯** _getProviders_              |       - |       - |  54,330 |     1 |       - |
|     **◯** _isOperational_             |       - |       - |  12,518 |     2 |       - |
|     **◯** _isOperationalForPegout_    |   7,905 |  12,540 |  10,223 |     2 |       - |
|        *register*                     | 200,944 | 239,737 | 220,341 |     4 |       - |
| **ProxyAdmin**                        |         |         |         |       |         |
|     **◯** _owner_                     |       - |       - |      96 |     4 |       - |
|     **◯** _UPGRADE_INTERFACE_VERSION_ |       - |       - |     567 |     1 |       - |
|        *upgradeAndCall*               |       - |       - |  37,821 |     1 |       - |

## Deployments

|                                  | Min | Max |       Avg | Block % | usd avg |
| :------------------------------- | --: | --: | --------: | ------: | ------: |
| **BridgeMock**                   |   - |   - | 1,010,222 |   3.4 % |       - |
| **BtcUtils**                     |   - |   - | 2,027,187 |   6.8 % |       - |
| **CollateralManagementContract** |   - |   - | 1,579,208 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,618,189 |   5.4 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,554,548 |   8.5 % |       - |
| **LiquidityBridgeContract**      |   - |   - | 5,292,711 |  17.6 % |       - |
| **LiquidityBridgeContractV2**    |   - |   - | 5,360,117 |  17.9 % |       - |
| **Quotes**                       |   - |   - |   634,029 |   2.1 % |       - |
| **QuotesV2**                     |   - |   - |   662,913 |   2.2 % |       - |
| **SignatureValidatorMock**       |   - |   - |   138,348 |   0.5 % |       - |

## Solidity and Network Config

| **Settings**        | **Value**  |
| ------------------- | ---------- |
| Solidity: version   | 0.8.25     |
| Solidity: optimized | true       |
| Solidity: runs      | 1          |
| Solidity: viaIR     | false      |
| Block Limit         | 30,000,000 |
| Gas Price           | -          |
| Token Price         | -          |
| Network             | ETHEREUM   |
| Toolchain           | hardhat    |

## Three liquidity providers

## Methods

| **Symbol** | **Meaning**                                                                              |
| :--------: | :--------------------------------------------------------------------------------------- |
|   **◯**    | Execution gas for this method does not include intrinsic gas overhead                    |
|   **△**    | Cost was non-zero but below the precision setting for the currency display (see options) |

|                                       |     Min |     Max |     Avg | Calls | usd avg |
| :------------------------------------ | ------: | ------: | ------: | ----: | ------: |
| **CollateralManagementContract**      |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  21,368 |  26,445 |  23,934 |     3 |       - |
|     **◯** _getProviders_              |       - |       - |  93,189 |     1 |       - |
|     **◯** _isOperational_             |  21,257 |  43,532 |  32,348 |     9 |       - |
|        *register*                     | 205,379 | 253,280 | 221,410 |     6 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,426 |     1 |       - |
|     **◯** _getProvider_               |  21,561 |  26,632 |  24,124 |     3 |       - |
|     **◯** _getProviders_              |       - |       - |  72,153 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,794 |  32,807 |  21,644 |     9 |       - |
|        *register*                     | 179,155 | 218,341 | 192,237 |     6 |       - |
| **LiquidityBridgeContractV2**         |         |         |         |       |         |
|     **◯** _getProvider_               |  24,376 |  29,274 |  26,825 |     3 |       - |
|     **◯** _getProviders_              |       - |       - |  80,551 |     1 |       - |
|     **◯** _isOperational_             |   7,883 |  12,518 |  10,973 |     3 |       - |
|     **◯** _isOperationalForPegout_    |   7,905 |  12,540 |  10,995 |     3 |       - |
|        *register*                     | 200,944 | 239,737 | 214,201 |     6 |       - |
| **ProxyAdmin**                        |         |         |         |       |         |
|     **◯** _owner_                     |       - |       - |      96 |     4 |       - |
|     **◯** _UPGRADE_INTERFACE_VERSION_ |       - |       - |     567 |     1 |       - |
|        *upgradeAndCall*               |       - |       - |  37,821 |     1 |       - |

## Deployments

|                                  | Min | Max |       Avg | Block % | usd avg |
| :------------------------------- | --: | --: | --------: | ------: | ------: |
| **BridgeMock**                   |   - |   - | 1,010,222 |   3.4 % |       - |
| **BtcUtils**                     |   - |   - | 2,027,187 |   6.8 % |       - |
| **CollateralManagementContract** |   - |   - | 1,579,208 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,618,189 |   5.4 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,554,548 |   8.5 % |       - |
| **LiquidityBridgeContract**      |   - |   - | 5,292,711 |  17.6 % |       - |
| **LiquidityBridgeContractV2**    |   - |   - | 5,360,117 |  17.9 % |       - |
| **Quotes**                       |   - |   - |   634,029 |   2.1 % |       - |
| **QuotesV2**                     |   - |   - |   662,913 |   2.2 % |       - |
| **SignatureValidatorMock**       |   - |   - |   138,348 |   0.5 % |       - |

## Solidity and Network Config

| **Settings**        | **Value**  |
| ------------------- | ---------- |
| Solidity: version   | 0.8.25     |
| Solidity: optimized | true       |
| Solidity: runs      | 1          |
| Solidity: viaIR     | false      |
| Block Limit         | 30,000,000 |
| Gas Price           | -          |
| Token Price         | -          |
| Network             | ETHEREUM   |
| Toolchain           | hardhat    |

## Four liquidity providers

## Methods

| **Symbol** | **Meaning**                                                                              |
| :--------: | :--------------------------------------------------------------------------------------- |
|   **◯**    | Execution gas for this method does not include intrinsic gas overhead                    |
|   **△**    | Cost was non-zero but below the precision setting for the currency display (see options) |

|                                       |     Min |     Max |     Avg | Calls | usd avg |
| :------------------------------------ | ------: | ------: | ------: | ----: | ------: |
| **CollateralManagementContract**      |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  21,368 |  28,900 |  25,176 |     4 |       - |
|     **◯** _getProviders_              |       - |       - | 119,541 |     1 |       - |
|     **◯** _isOperational_             |  21,257 |  48,328 |  35,951 |    12 |       - |
|        *register*                     | 205,379 | 253,280 | 225,103 |     8 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,426 |     1 |       - |
|     **◯** _getProvider_               |  21,561 |  29,084 |  25,364 |     4 |       - |
|     **◯** _getProviders_              |       - |       - |  95,352 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,794 |  38,057 |  25,277 |    12 |       - |
|        *register*                     | 179,155 | 218,341 | 194,488 |     8 |       - |
| **LiquidityBridgeContractV2**         |         |         |         |       |         |
|     **◯** _getProvider_               |  24,376 |  31,723 |  28,050 |     4 |       - |
|     **◯** _getProviders_              |       - |       - | 103,386 |     1 |       - |
|     **◯** _isOperational_             |   7,883 |  12,518 |  11,359 |     4 |       - |
|     **◯** _isOperationalForPegout_    |   7,905 |  12,540 |  11,381 |     4 |       - |
|        *register*                     | 200,944 | 239,737 | 216,310 |     8 |       - |
| **ProxyAdmin**                        |         |         |         |       |         |
|     **◯** _owner_                     |       - |       - |      96 |     4 |       - |
|     **◯** _UPGRADE_INTERFACE_VERSION_ |       - |       - |     567 |     1 |       - |
|        *upgradeAndCall*               |       - |       - |  37,821 |     1 |       - |

## Deployments

|                                  | Min | Max |       Avg | Block % | usd avg |
| :------------------------------- | --: | --: | --------: | ------: | ------: |
| **BridgeMock**                   |   - |   - | 1,010,222 |   3.4 % |       - |
| **BtcUtils**                     |   - |   - | 2,027,187 |   6.8 % |       - |
| **CollateralManagementContract** |   - |   - | 1,579,208 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,618,189 |   5.4 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,554,548 |   8.5 % |       - |
| **LiquidityBridgeContract**      |   - |   - | 5,292,711 |  17.6 % |       - |
| **LiquidityBridgeContractV2**    |   - |   - | 5,360,117 |  17.9 % |       - |
| **Quotes**                       |   - |   - |   634,029 |   2.1 % |       - |
| **QuotesV2**                     |   - |   - |   662,913 |   2.2 % |       - |
| **SignatureValidatorMock**       |   - |   - |   138,348 |   0.5 % |       - |

## Solidity and Network Config

| **Settings**        | **Value**  |
| ------------------- | ---------- |
| Solidity: version   | 0.8.25     |
| Solidity: optimized | true       |
| Solidity: runs      | 1          |
| Solidity: viaIR     | false      |
| Block Limit         | 30,000,000 |
| Gas Price           | -          |
| Token Price         | -          |
| Network             | ETHEREUM   |
| Toolchain           | hardhat    |

## Five liquidity providers

## Methods

| **Symbol** | **Meaning**                                                                              |
| :--------: | :--------------------------------------------------------------------------------------- |
|   **◯**    | Execution gas for this method does not include intrinsic gas overhead                    |
|   **△**    | Cost was non-zero but below the precision setting for the currency display (see options) |

|                                       |     Min |     Max |     Avg | Calls | usd avg |
| :------------------------------------ | ------: | ------: | ------: | ----: | ------: |
| **CollateralManagementContract**      |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,382 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,833 |     2 |       - |
| **FlyoverDiscoveryContract**          |         |         |         |       |         |
|     **◯** _getProvider_               |  21,368 |  31,355 |  26,412 |     5 |       - |
|     **◯** _getProviders_              |       - |       - | 146,335 |     1 |       - |
|     **◯** _isOperational_             |  21,257 |  50,793 |  38,605 |    15 |       - |
|        *register*                     | 205,379 | 253,280 | 227,318 |    10 |       - |
| **FlyoverDiscoveryFull**              |         |         |         |       |         |
|     **◯** _COLLATERAL_ADDER_          |       - |       - |   5,426 |     1 |       - |
|     **◯** _getProvider_               |  21,561 |  31,536 |  26,599 |     5 |       - |
|     **◯** _getProviders_              |       - |       - | 117,657 |     1 |       - |
|        *grantRole*                    |       - |       - |  56,855 |     2 |       - |
|     **◯** _isOperational_             |  10,794 |  40,528 |  28,010 |    15 |       - |
|        *register*                     | 179,155 | 218,341 | 195,839 |    10 |       - |
| **LiquidityBridgeContractV2**         |         |         |         |       |         |
|     **◯** _getProvider_               |  24,376 |  34,172 |  29,274 |     5 |       - |
|     **◯** _getProviders_              |       - |       - | 125,661 |     1 |       - |
|     **◯** _isOperational_             |   7,883 |  12,518 |  11,591 |     5 |       - |
|     **◯** _isOperationalForPegout_    |   7,905 |  12,540 |  11,613 |     5 |       - |
|        *register*                     | 200,944 | 239,737 | 217,576 |    10 |       - |
| **ProxyAdmin**                        |         |         |         |       |         |
|     **◯** _owner_                     |       - |       - |      96 |     4 |       - |
|     **◯** _UPGRADE_INTERFACE_VERSION_ |       - |       - |     567 |     1 |       - |
|        *upgradeAndCall*               |       - |       - |  37,821 |     1 |       - |

## Deployments

|                                  | Min | Max |       Avg | Block % | usd avg |
| :------------------------------- | --: | --: | --------: | ------: | ------: |
| **BridgeMock**                   |   - |   - | 1,010,222 |   3.4 % |       - |
| **BtcUtils**                     |   - |   - | 2,027,187 |   6.8 % |       - |
| **CollateralManagementContract** |   - |   - | 1,579,208 |   5.3 % |       - |
| **FlyoverDiscoveryContract**     |   - |   - | 1,618,189 |   5.4 % |       - |
| **FlyoverDiscoveryFull**         |   - |   - | 2,554,548 |   8.5 % |       - |
| **LiquidityBridgeContract**      |   - |   - | 5,292,711 |  17.6 % |       - |
| **LiquidityBridgeContractV2**    |   - |   - | 5,360,117 |  17.9 % |       - |
| **Quotes**                       |   - |   - |   634,029 |   2.1 % |       - |
| **QuotesV2**                     |   - |   - |   662,913 |   2.2 % |       - |
| **SignatureValidatorMock**       |   - |   - |   138,348 |   0.5 % |       - |

## Solidity and Network Config

| **Settings**        | **Value**  |
| ------------------- | ---------- |
| Solidity: version   | 0.8.25     |
| Solidity: optimized | true       |
| Solidity: runs      | 1          |
| Solidity: viaIR     | false      |
| Block Limit         | 30,000,000 |
| Gas Price           | -          |
| Token Price         | -          |
| Network             | ETHEREUM   |
| Toolchain           | hardhat    |
