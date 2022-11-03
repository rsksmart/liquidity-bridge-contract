// should register liquidity provider
//
// Should fail on register if is already registered
//
// Should fail on register if not deposit the minimum collateral
//
// Should fail on register if where resigned but not withdrawn
//
// should not register lp again
//
// should not register lp with not enough collateral
//
// should fail to register liquidity provider from a contract

Feature: User Register as a Bridge/LP

  Scenario: Should register User as a Liquidity Provider
    When User register as LP for the first time
    Then User is registered as LP

