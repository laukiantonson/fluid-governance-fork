# Close Down the dexV1 Test DEX, Rebalance Vault 3, Launch the weETH/ETH Vault, Remove Team Multisig wstETH/cbBTC Borrow Limits, and Close Down IGP-45 Test DEXes id1/id3

> **DRAFT.** Actions are added as they are agreed in #gov-proposals-lineup.

## Summary

This proposal fully restricts the Liquidity Layer limits of the early **dexV1 test DEX** (wstETH/ETH, `0x6d83...e03a`) so it can no longer withdraw or borrow, rebalances the **wstETH/ETH T1 vault (3)** borrow side that is stuck behind its dust borrow limit, raises the **weETH/ETH T1 vault (182)** from the IGP-140 dust limits to launch limits, reduces the **Team Multisig** wstETH and cbBTC borrow limits on the Liquidity Layer to dust, and fully restricts the Liquidity Layer limits of the IGP-45 test DEXes **id1** (wstETH/ETH) and **id3** (WBTC/cbBTC).

## Code Changes

### Action 1: Fully Restrict the dexV1 Test DEX at the Liquidity Layer

- **DEX**: `0x6d83f60eEac0e50A1250760151E81Db2a278e03a` (wstETH / ETH, early dexV1 test deployment, not deployed by the DexFactory)
- **Tokens**: wstETH (`0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0`), ETH (`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`)

| Step | Call | Effect |
| --- | --- | --- |
| Borrow | `setBorrowProtocolLimitsPaused` for wstETH and ETH | Debt ceiling `10 / 20` (dust), expansion 0.01% over max duration |
| Supply | `setSupplyProtocolLimitsPaused` for wstETH and ETH | Base withdrawal limit `10` (dust), expansion 0.01% over max duration |
| Withdrawal limit | `updateUserWithdrawalLimit(dex, token, type(uint256).max)` for wstETH and ETH | Current withdrawal limit set to the full user supply, withdrawable `0` |

The last step matters: with only the supply restriction, the first operation after execution could still withdraw the full residual once (the withdrawal limit is only recomputed on the next operate). Setting the limit to the full supply closes that.

**Ordering:** the Team Multisig closes its position in this DEX before this proposal executes (swap/arbitrage pause, then withdraw and payback). If this action executes first, the Team Multisig can no longer withdraw.

### Action 2: Rebalance the wstETH/ETH T1 Vault (3)

- **Vault**: `0xA0F83Fc5885cEBc0420ce7C7b139Adc80c4F4D91` (T1, wstETH collateral / ETH debt)
- **Rebalancer**: Reserve Contract (`0x264786EF916af64a1DB19F513F24a3681734ce92`)

The vault's own total borrow is **≈0.00493 ETH** above its borrow at the Liquidity Layer. `rebalance()` borrows that difference to the Reserve, but the vault's Liquidity Layer ETH borrow limit is at dust (`11 / 22`), so the borrow fails and the rebalancer skips it.

| Step | Call |
| --- | --- |
| 1 | Raise the vault's ETH debt ceiling at the Liquidity Layer to `1e18` raw (≈1 ETH; vault borrow ≈0.454 ETH) |
| 2 | `FLUID_RESERVE.updateRebalancer(TIMELOCK, true)`, `rebalanceVaults([vault 3], [0])`, `updateRebalancer(TIMELOCK, false)` |
| 3 | Restore the dust ETH debt ceiling via `setBorrowProtocolLimitsPaused` |

The supply-side difference (≈135 wei wstETH) is below Liquidity Layer storage precision (`UserModule__OperateAmountInsufficient`), so the vault's try/catch skips it. No Reserve allowance is needed.

### Action 3: Launch Limits for the weETH/ETH T1 Vault (182)

- **Vault**: `getVaultAddress(182)` = `0x0b8a681eD46EA8ec6b97d686dF0631Fbf84B03D2` (T1, weETH collateral / ETH debt)

| Parameter | Current (IGP-140) | New |
| --- | --- | --- |
| Base withdrawal limit | ≈$7k | **$8M** |
| Base borrow limit | ≈$7k | **$15M** |
| Max borrow limit | ≈$9k | **$30M** |

- Set via `setVaultLimits` with the standard T1 expansion (50% over 6 hours).
- Risk parameters (CF 94% / LT 96% / LML 97% / LP 1%) were set by the Team Multisig. Team Multisig vault auth (granted in IGP-140) is kept for the pending OracleV2 switch.

### Action 4: Reduce Team Multisig wstETH & cbBTC Borrow Limits to Dust

- **User**: Team Multisig `0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e`
- **Tokens**: wstETH (`0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0`), cbBTC (`0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf`)

| Parameter | Current (IGP-107 DEX Lite credit) | New |
| --- | --- | --- |
| Base / max debt ceiling | $1M each (≈185 wstETH, ≈9.1 cbBTC borrowable) | **`10 / 20` wei** |
| Expansion | 1% over max duration | 0.01% over max duration |

- Calls `setBorrowProtocolLimitsPaused(TEAM_MULTISIG, token)` for wstETH and cbBTC, the same treatment USDC and USDT received in IGP-132 (action 2).
- Both credit lines are unused (0 debt). Mode 1 (with interest) matches the existing config, so no mode switch is triggered.

### Action 5: Fully Restrict IGP-45 Test DEXes id1 and id3 at the Liquidity Layer

- **dex id1**: `0x25F0A3B25cBC0Ca0417770f686209628323fF901` (wstETH / ETH, old DexFactory), tokens wstETH + ETH
- **dex id3**: `0x1d3e52a11B98Ed2AAB7eB0Bfe1cbB6525233204d` (WBTC / cbBTC, old DexFactory), tokens WBTC (`0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599`) + cbBTC (`0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf`)

Same three steps as Action 1 for each DEX and token: `setBorrowProtocolLimitsPaused` (debt ceiling `10 / 20`), `setSupplyProtocolLimitsPaused` (base withdrawal limit `10`), `updateUserWithdrawalLimit(dex, token, type(uint256).max)` (withdrawable `0`).

| DEX | LL supply today | Base withdrawal limit today | Borrow side today |
| --- | --- | --- | --- |
| id1 | 0.0185 wstETH + 0.0227 ETH (≈$124) | 17.29 wstETH / 21.21 ETH (25% / 12h) | already non-borrowable (limit below borrow), 20% / 12h |
| id3 | 0.00202 WBTC + 0.00202 cbBTC (≈$343) | 0.807 WBTC / 0.808 cbBTC (25% / 12h) | already non-borrowable (limit below borrow), 20% / 12h |

- **Residual stays locked.** id1: the only user is vault 34 with a single position (NFT 2296); the rest is the locked initial shares. id3: no user holds shares (vaults 41/42/43 whitelisted, all at 0); the residual is the locked initial shares only.

## Description

1. **dexV1 test DEX**: closes out the last live Liquidity Layer limits of an early test deployment after the Team Multisig exits its position.
2. **Vault 3 rebalance**: clears the borrow-side drift the rebalancer cannot reach while the vault sits at dust borrow limits, and returns it to dust in the same action.
3. **weETH/ETH vault**: moves vault 182 from dust to launch limits.
4. **Team Multisig credit**: closes the unused IGP-107 wstETH and cbBTC DEX Lite credit lines, matching the USDC/USDT cut in IGP-132.
5. **IGP-45 test DEXes id1/id3**: closes the Liquidity Layer limits of two early test DEXes holding only dust.

## Conclusion

IGP-141 closes the dexV1 test DEX at the Liquidity Layer, rebalances vault 3 without leaving any borrow capacity open, launches the weETH/ETH vault, closes the Team Multisig's remaining wstETH/cbBTC credit lines, and closes the IGP-45 test DEXes id1/id3 at the Liquidity Layer.
