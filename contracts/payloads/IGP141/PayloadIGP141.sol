// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.21;
pragma experimental ABIEncoderV2;

import {PayloadIGPPriceHelpers} from "../common/pricehelpers.sol";
import {
    AdminModuleStructs as FluidLiquidityAdminStructs
} from "../common/interfaces/IFluidLiquidity.sol";
import {IDSAV2} from "../common/interfaces/IDSA.sol";

/// @notice Liquidity Layer admin call not exposed on the shared
///         IFluidLiquidityAdmin interface. Signature added to the Liquidity
///         AdminModule in IGP-37.
interface IFluidLiquidityWithdrawalLimit {
    function updateUserWithdrawalLimit(
        address user_,
        address token_,
        uint256 newLimit_
    ) external;
}

/// @notice IGP141 (DRAFT): Close down the dexV1 test DEX at the Liquidity
///         Layer, rebalance vault 3 (wstETH/ETH), and raise the weETH/ETH
///         vault (182) from dust to launch limits. More actions are added as
///         they are agreed in #gov-proposals-lineup.
///
///         Action 1 fully restricts the Liquidity Layer supply and borrow
///         limits of the dexV1 test DEX 0x6d83...e03a (wstETH/ETH, deployed
///         from the early MS1 test factory, never part of the DexFactory)
///         and pins its current withdrawal limit to its full supply, so no
///         further withdrawal or borrow can happen. Must execute AFTER the
///         Team Multisig has closed its position in that DEX.
///
///         Action 2 rebalances vault 3 (wstETH/ETH). Its ETH borrow at the
///         Liquidity Layer is ~0.0049 ETH below the vault's own total borrow,
///         and the rebalance cannot borrow the difference while the vault's
///         Liquidity Layer borrow limit is at dust. The action raises the
///         limit, runs the rebalance through the Reserve Contract (the
///         vault's rebalancer), and restores the dust limit.
///
///         Action 3 raises the weETH/ETH T1 vault (182) from the IGP-140 dust
///         limits to launch limits.
///
///         Action 4 reduces the Team Multisig's wstETH and cbBTC borrow limits
///         at the Liquidity Layer (IGP-107 DEX Lite credit) to dust, the same
///         treatment USDC and USDT received in IGP-132.
///
///         Action 5 exits iETHv2's residual test positions (old vault #3
///         NFT 18, vault 34 NFT 2296) through its DSA before Actions 6 and
///         7 freeze them. The Timelock sends 0.005 ETH for the ETH leg of
///         the vault 34 repayment; about $67 returns to iETHv2.
///
///         Action 6 fully restricts the Liquidity Layer supply and borrow
///         limits of the IGP-45 test DEXes dex id1 wstETH/ETH 0x25F0...F901
///         and dex id3 WBTC/cbBTC 0x1d3e...204d (old DexFactory), same
///         pattern as Action 1. The residual supply (vault 34 dust + locked
///         init shares) stays locked.
///
///         Action 7 fully restricts and pauses at the Liquidity Layer the
///         five pre-launch vaults of the old VaultFactory (0x3B38...8C60,
///         closed in IGP-24), the old DexFactory dex id1 / dex id3, and the
///         Liquidity Layer debt configs of the T2 vaults 42 / 43 on dex id3.
///
///         Action 8 restricts and pauses at the Liquidity Layer the last
///         IGP-45 test DEX, dex id2 (USDC/USDT), and the six empty T3
///         vaults 35-40 built on it.
contract PayloadIGP141 is PayloadIGPPriceHelpers {
    uint256 public constant PROPOSAL_ID = 141;

    // --- Action 1 ---
    /// @dev dexV1 test DEX (wstETH/ETH). Not deployed by the DexFactory, so
    ///      it cannot be resolved via getDexAddress().
    address public constant DEX_V1_TEST =
        0x6d83f60eEac0e50A1250760151E81Db2a278e03a;

    // --- Action 2 ---
    uint256 public constant VAULT_WSTETH_ETH_ID = 3; // T1: wstETH / ETH
    /// @dev Temporary raw ETH borrow limit (with-interest mode) for the
    ///      rebalance. Live vault borrow is ~0.454 ETH, so ~1 ETH leaves
    ///      room for the ~0.0049 ETH drift. Reset to dust in the same action.
    uint256 public constant VAULT_3_TEMP_BORROW_LIMIT_RAW = 1 ether;

    // --- Action 3 ---
    uint256 public constant VAULT_WEETH_ETH_ID = 182; // T1: weETH / ETH

    // --- Action 5 ---
    /// @dev FLUID-VAULT-T4-A connector input (operatePerfect)
    struct T4OperatePerfect {
        address vaultAddress;
        uint256 nftId;
        int256 perfectColShares;
        int256 colToken0MinMax;
        int256 colToken1MinMax;
        int256 perfectDebtShares;
        int256 debtToken0MinMax;
        int256 debtToken1MinMax;
        uint256 getNftId;
        uint256[] setIds;
    }

    /// @dev iETHv2 strategy DSA (#36121). Auths: iETHv2 vault + Timelock.
    address public constant IETHV2_DSA =
        0x9600A48ed0f931d0c422D574e3275a90D8b22745;
    /// @dev T4 wstETH/ETH vault on old dex id1.
    address public constant VAULT_34_WSTETH_ETH_T4 =
        0x57fed7c9b3c763999c519264931790cBcA331417;

    // --- Action 6 ---
    /// @dev IGP-45 test DEXes, deployed from the old DexFactory, so they
    ///      cannot be resolved via getDexAddress().
    address public constant OLD_DEX_ID1_WSTETH_ETH =
        0x25F0A3B25cBC0Ca0417770f686209628323fF901;
    address public constant OLD_DEX_ID3_WBTC_CBBTC =
        0x1d3e52a11B98Ed2AAB7eB0Bfe1cbB6525233204d;

    // --- Action 8 ---
    /// @dev IGP-45 test dex id2 (USDC/USDT), old DexFactory. Only DEX-level
    ///      users are the T3 vaults 35-40.
    address public constant OLD_DEX_ID2_USDC_USDT =
        0x085B07A30381F3Cc5A4250e10E4379d465b770ac;

    // --- Action 7 ---
    /// @dev Pre-launch vaults from the old VaultFactory 0x3B38...8C60
    ///      (closed in IGP-24). Not resolvable via getVaultAddress().
    address public constant OLD_VAULT_1_ETH_USDC =
        0x5eA9A2B42Bc9aC8CAC76E19F0Fcd5C1b06950807;
    address public constant OLD_VAULT_2_ETH_USDT =
        0xE53794f2ed0839F24170079A9F3c5368147F6c81;
    address public constant OLD_VAULT_3_WSTETH_ETH =
        0x28680f14C4Bb86B71119BC6e90E4e6D87E6D1f51;
    address public constant OLD_VAULT_4_WSTETH_USDC =
        0x460143a489729a3cA32DeA82fa48ea61175accbc;
    address public constant OLD_VAULT_5_WSTETH_USDT =
        0x2B251211f5Ff0A753A8d5B9411d736875174f375;
    /// @dev T2 vaults on old dex id3 (live VaultFactory ids) with debt
    ///      configured directly at the Liquidity Layer.
    uint256 public constant VAULT_42_ID = 42; // T2 on dex id3, USDC debt
    uint256 public constant VAULT_43_ID = 43; // T2 on dex id3, USDT debt

    function execute() public virtual override {
        super.execute();

        // Action 1: Fully restrict the dexV1 test DEX at the Liquidity Layer.
        action1();

        // Action 2: Rebalance vault 3 (wstETH/ETH) and restore its dust limit.
        action2();

        // Action 3: Raise weETH/ETH vault (182) to launch limits.
        action3();

        // Action 4: Reduce Team Multisig wstETH & cbBTC borrow limits to dust.
        action4();

        // Action 5: iETHv2 DSA exits its residual test positions (must run before 6 and 7).
        action5();

        // Action 6: Fully restrict IGP-45 test dex id1 and dex id3 at the Liquidity Layer.
        action6();

        // Action 7: Restrict + pause old pre-launch vaults and old dex id1 / id3 at the Liquidity Layer.
        action7();

        // Action 8: Restrict + pause old dex id2 (USDC/USDT) and T3 vaults 35-40 at the Liquidity Layer.
        action8();
    }

    function verifyProposal() public view override {}

    function _PROPOSAL_ID() internal view override returns (uint256) {
        return PROPOSAL_ID;
    }

    /**
     * |
     * |     Proposal Payload Actions      |
     * |__________________________________
     */

    /// @notice Action 1: Fully restrict the dexV1 test DEX
    ///         (0x6d83...e03a, wstETH/ETH) at the Liquidity Layer.
    ///         - borrow: dust debt ceiling (10 / 20) for wstETH and ETH
    ///         - supply: dust base withdrawal limit (10) for wstETH and ETH
    ///         - current withdrawal limit set to the full user supply for
    ///           both tokens (updateUserWithdrawalLimit with a limit above
    ///           supply), so the residual cannot be withdrawn even once.
    ///         Without the last step the first operation after the supply
    ///         restriction could still withdraw the full residual (fork sim).
    function action1() internal isActionSkippable(1) {
        setBorrowProtocolLimitsPaused(DEX_V1_TEST, wstETH_ADDRESS);
        setBorrowProtocolLimitsPaused(DEX_V1_TEST, ETH_ADDRESS);

        setSupplyProtocolLimitsPaused(DEX_V1_TEST, wstETH_ADDRESS);
        setSupplyProtocolLimitsPaused(DEX_V1_TEST, ETH_ADDRESS);

        IFluidLiquidityWithdrawalLimit(address(LIQUIDITY))
            .updateUserWithdrawalLimit(
                DEX_V1_TEST,
                wstETH_ADDRESS,
                type(uint256).max
            );
        IFluidLiquidityWithdrawalLimit(address(LIQUIDITY))
            .updateUserWithdrawalLimit(
                DEX_V1_TEST,
                ETH_ADDRESS,
                type(uint256).max
            );
    }

    /// @notice Action 2: Rebalance vault 3 (wstETH/ETH).
    ///         1. Raise the vault's ETH borrow limit at the Liquidity Layer
    ///            from dust to ~1 ETH.
    ///         2. Allow-list the Timelock as Reserve rebalancer, call
    ///            rebalanceVaults([vault 3]), remove the Timelock again.
    ///            The borrow drift (~0.0049 ETH) is borrowed to the Reserve.
    ///         3. Restore the dust ETH borrow limit (10 / 20).
    ///         The supply-side drift (~136 wei wstETH) is below Liquidity
    ///         Layer storage precision (UserModule__OperateAmountInsufficient),
    ///         so the vault's try/catch skips it; no Reserve allowance needed.
    function action2() internal isActionSkippable(2) {
        address vault_ = getVaultAddress(VAULT_WSTETH_ETH_ID);

        // Step 1: temporary borrow limit.
        {
            FluidLiquidityAdminStructs.UserBorrowConfig[]
                memory configs_ = new FluidLiquidityAdminStructs.UserBorrowConfig[](
                    1
                );
            configs_[0] = FluidLiquidityAdminStructs.UserBorrowConfig({
                user: vault_,
                token: ETH_ADDRESS,
                mode: 1,
                expandPercent: 1, // 0.01%
                expandDuration: 16777215, // max time
                baseDebtCeiling: VAULT_3_TEMP_BORROW_LIMIT_RAW,
                maxDebtCeiling: VAULT_3_TEMP_BORROW_LIMIT_RAW
            });
            LIQUIDITY.updateUserBorrowConfigs(configs_);
        }

        // Step 2: rebalance through the Reserve (vault 3's rebalancer).
        FLUID_RESERVE.updateRebalancer(address(TIMELOCK), true);
        {
            address[] memory protocols_ = new address[](1);
            uint256[] memory values_ = new uint256[](1);

            protocols_[0] = vault_;
            values_[0] = 0;

            FLUID_RESERVE.rebalanceVaults(protocols_, values_);
        }
        FLUID_RESERVE.updateRebalancer(address(TIMELOCK), false);

        // Step 3: restore the dust borrow limit.
        setBorrowProtocolLimitsPaused(vault_, ETH_ADDRESS);
    }

    /// @notice Action 3: Raise the weETH/ETH T1 vault (182) from IGP-140
    ///         dust limits to launch limits (risk params per Ishan):
    ///         base withdrawal $8M, base borrow $15M, max borrow $30M,
    ///         standard T1 expansion (50% / 6h). Team Multisig vault auth
    ///         (granted in IGP-140) is kept for the pending OracleV2 switch.
    function action3() internal isActionSkippable(3) {
        VaultConfig memory VAULT_WEETH_ETH = VaultConfig({
            vault: getVaultAddress(VAULT_WEETH_ETH_ID),
            vaultType: VAULT_TYPE.TYPE_1,
            supplyToken: weETH_ADDRESS,
            borrowToken: ETH_ADDRESS,
            baseWithdrawalLimitInUSD: 8_000_000, // $8M
            baseBorrowLimitInUSD: 15_000_000, // $15M
            maxBorrowLimitInUSD: 30_000_000 // $30M
        });

        setVaultLimits(VAULT_WEETH_ETH);
    }

    /// @notice Action 4: Reduce the Team Multisig's wstETH & cbBTC borrow
    ///         limits on the Liquidity Layer to dust (base 10 / max 20 wei).
    /// @dev Same treatment as USDC & USDT in IGP-132 (action 2). The IGP-107
    ///      DEX Lite credit lines ($1M wstETH, $1M cbBTC) are unused (0 debt).
    ///      The AdminModule reverts `LimitZero` on a literal zero, so base 10 /
    ///      max 20 wei is the canonical dust limit. Mode 1 (with interest)
    ///      matches the existing config for both tokens, so no mode switch.
    function action4() internal isActionSkippable(4) {
        setBorrowProtocolLimitsPaused(TEAM_MULTISIG, wstETH_ADDRESS);
        setBorrowProtocolLimitsPaused(TEAM_MULTISIG, cbBTC_ADDRESS);
    }

    /// @notice Action 5: iETHv2's DSA exits its residual test positions
    ///         (old vault #3 NFT 18, vault 34 NFT 2296) before Actions 6
    ///         and 7 freeze them.
    /// @dev Only governance can move these: the DSA's auths are the iETHv2
    ///      vault and the Timelock, and iETHv2's spell() is proxy-admin
    ///      (Timelock) only. Cast directly on the DSA, like IGP-109 on
    ///      TREASURY.
    ///      - NFT 18: 0.01 wstETH, no debt, plain max withdraw. Frees the
    ///        wstETH for the vault 34 wstETH debt leg.
    ///      - NFT 2296: vault 34 books 4,000,002 more debt shares than dex
    ///        id1 records for it, so a max payback underflows. Repay the
    ///        4e15 dex-side shares explicitly (4,000,005 dust shares stay),
    ///        and keep 1e13 col shares (0.1%) behind that dust.
    ///      - The DSA holds no ETH; the Timelock sends 0.005 ETH with the
    ///        cast for the ETH leg (~0.00421 needed), unused ETH is refunded.
    ///        Payback caps 0.0045 wstETH / 0.005 ETH leave 30% / 19% headroom.
    ///      - try/catch: anyone can partially repay NFT 2296, which would
    ///        make the fixed share amount revert; that must not block the
    ///        rest of the IGP. Verify by DSA balances, not tx status.
    function action5() internal isActionSkippable(5) {
        string[] memory targets_ = new string[](2);
        bytes[] memory datas_ = new bytes[](2);

        // old vault #3 NFT 18: withdraw all 0.01 wstETH
        targets_[0] = "FLUID-A";
        datas_[0] = abi.encodeWithSignature(
            "operate(address,uint256,int256,int256,uint256)",
            OLD_VAULT_3_WSTETH_ETH,
            18,
            type(int256).min,
            int256(0),
            0
        );

        // vault 34 NFT 2296: repay the dex-side debt shares, withdraw all but 0.1% of the collateral
        targets_[1] = "FLUID-VAULT-T4-A";
        datas_[1] = abi.encodeWithSelector(
            bytes4(
                keccak256(
                    "operatePerfect((address,uint256,int256,int256,int256,int256,int256,int256,uint256,uint256[]))"
                )
            ),
            T4OperatePerfect({
                vaultAddress: VAULT_34_WSTETH_ETH_T4,
                nftId: 2296,
                perfectColShares: -9_990_000_000_000_000,
                colToken0MinMax: -1,
                colToken1MinMax: -1,
                perfectDebtShares: -4_000_000_000_000_000,
                debtToken0MinMax: -0.0045 ether,
                debtToken1MinMax: -0.005 ether,
                getNftId: 0,
                setIds: new uint256[](6)
            })
        );

        try
            IDSAV2(IETHV2_DSA).cast{value: 0.005 ether}(
                targets_,
                datas_,
                address(this)
            )
        {} catch {}
    }

    /// @notice Action 6: Fully restrict the IGP-45 test DEXes (old
    ///         DexFactory) at the Liquidity Layer, same pattern as Action 1:
    ///         - dex id1 wstETH/ETH (0x25F0...F901), tokens wstETH + ETH
    ///         - dex id3 WBTC/cbBTC (0x1d3e...204d), tokens WBTC + cbBTC
    ///         Borrow to dust (10 / 20), supply base withdrawal limit to dust
    ///         (10), and current withdrawal limit pinned to the full user
    ///         supply so the residual cannot be withdrawn even once.
    /// @dev Borrow side is already non-borrowable (limit below current
    ///      borrow) but still on the 20% / 12h expand config; this pins it.
    ///      id1 residual includes vault 34's dust position (NFT 2296, after
    ///      Action 5); id3 residual is the locked initial shares only.
    function action6() internal isActionSkippable(6) {
        _fullyRestrictDex(
            OLD_DEX_ID1_WSTETH_ETH,
            wstETH_ADDRESS,
            ETH_ADDRESS
        );
        _fullyRestrictDex(
            OLD_DEX_ID3_WBTC_CBBTC,
            WBTC_ADDRESS,
            cbBTC_ADDRESS
        );
    }

    /// @notice Action 7: Fully restrict and pause the remaining old
    ///         protocols at the Liquidity Layer.
    ///         - old VaultFactory vaults #1-#5: supply + borrow limits to
    ///           dust, withdrawal limit pinned to full supply, supply and
    ///           borrow paused at the Liquidity Layer.
    ///         - T2 vaults 42 / 43 (smart col on dex id3): Liquidity Layer
    ///           debt limits to dust and paused.
    ///         - dex id1 / dex id3 (limits already dusted in Action 6):
    ///           paused at the Liquidity Layer for supply and borrow, which
    ///           also freezes the vaults built on them (34, 41, 42, 43).
    /// @dev DEX-level configs of the old-factory dexes are not governed by
    ///      the Timelock (DexT1__NotAnAuth), so no DEX-level calls here.
    function action7() internal isActionSkippable(7) {
        // old VaultFactory vaults: (supply token, borrow token)
        _restrictAndPauseVault(OLD_VAULT_1_ETH_USDC, ETH_ADDRESS, USDC_ADDRESS);
        _restrictAndPauseVault(OLD_VAULT_2_ETH_USDT, ETH_ADDRESS, USDT_ADDRESS);
        _restrictAndPauseVault(OLD_VAULT_3_WSTETH_ETH, wstETH_ADDRESS, ETH_ADDRESS);
        _restrictAndPauseVault(OLD_VAULT_4_WSTETH_USDC, wstETH_ADDRESS, USDC_ADDRESS);
        _restrictAndPauseVault(OLD_VAULT_5_WSTETH_USDT, wstETH_ADDRESS, USDT_ADDRESS);

        // T2 vaults 42 / 43 (smart col on dex id3, debt at the Liquidity Layer)
        _restrictAndPauseBorrow(getVaultAddress(VAULT_42_ID), USDC_ADDRESS);
        _restrictAndPauseBorrow(getVaultAddress(VAULT_43_ID), USDT_ADDRESS);

        // dex id1 / id3: pause at the Liquidity Layer
        _pauseUserAtLiquidity(OLD_DEX_ID1_WSTETH_ETH, wstETH_ADDRESS, ETH_ADDRESS);
        _pauseUserAtLiquidity(OLD_DEX_ID3_WBTC_CBBTC, WBTC_ADDRESS, cbBTC_ADDRESS);
    }

    /// @notice Action 8: Restrict and pause the last IGP-45 test DEX, old
    ///         dex id2 (USDC/USDT), and the T3 vaults 35-40 built on it at
    ///         the Liquidity Layer.
    ///         - dex id2: borrow limits to dust and borrow paused (no
    ///           supply configs; its ~$227 init debt stays locked).
    ///         - vaults 35-40: 0 positions, 0 supply, but supply configs
    ///           still open (25% / 12h). Supply limits to dust and paused.
    /// @dev All seven configs are already mode 1, so the dust configs cause
    ///      no mode switch.
    function action8() internal isActionSkippable(8) {
        setBorrowProtocolLimitsPaused(OLD_DEX_ID2_USDC_USDT, USDC_ADDRESS);
        setBorrowProtocolLimitsPaused(OLD_DEX_ID2_USDC_USDT, USDT_ADDRESS);
        address[] memory borrowTokens_ = new address[](2);
        borrowTokens_[0] = USDC_ADDRESS;
        borrowTokens_[1] = USDT_ADDRESS;
        LIQUIDITY.pauseUser(
            OLD_DEX_ID2_USDC_USDT,
            new address[](0),
            borrowTokens_
        );

        _restrictAndPauseSupply(getVaultAddress(35), ETH_ADDRESS);
        _restrictAndPauseSupply(getVaultAddress(36), wstETH_ADDRESS);
        _restrictAndPauseSupply(getVaultAddress(37), weETH_ADDRESS);
        _restrictAndPauseSupply(getVaultAddress(38), WBTC_ADDRESS);
        _restrictAndPauseSupply(getVaultAddress(39), cbBTC_ADDRESS);
        _restrictAndPauseSupply(getVaultAddress(40), sUSDe_ADDRESS);
    }

    function _restrictAndPauseSupply(address user_, address token_) internal {
        setSupplyProtocolLimitsPaused(user_, token_);
        address[] memory supplyTokens_ = new address[](1);
        supplyTokens_[0] = token_;
        LIQUIDITY.pauseUser(user_, supplyTokens_, new address[](0));
    }

    function _restrictAndPauseVault(
        address vault_,
        address supplyToken_,
        address borrowToken_
    ) internal {
        setSupplyProtocolLimitsPaused(vault_, supplyToken_);
        setBorrowProtocolLimitsPaused(vault_, borrowToken_);
        IFluidLiquidityWithdrawalLimit(address(LIQUIDITY))
            .updateUserWithdrawalLimit(vault_, supplyToken_, type(uint256).max);

        address[] memory supplyTokens_ = new address[](1);
        supplyTokens_[0] = supplyToken_;
        address[] memory borrowTokens_ = new address[](1);
        borrowTokens_[0] = borrowToken_;
        LIQUIDITY.pauseUser(vault_, supplyTokens_, borrowTokens_);
    }

    function _restrictAndPauseBorrow(address user_, address token_) internal {
        setBorrowProtocolLimitsPaused(user_, token_);

        address[] memory supplyTokens_ = new address[](0);
        address[] memory borrowTokens_ = new address[](1);
        borrowTokens_[0] = token_;
        LIQUIDITY.pauseUser(user_, supplyTokens_, borrowTokens_);
    }

    function _pauseUserAtLiquidity(
        address user_,
        address token0_,
        address token1_
    ) internal {
        address[] memory tokens_ = new address[](2);
        tokens_[0] = token0_;
        tokens_[1] = token1_;
        LIQUIDITY.pauseUser(user_, tokens_, tokens_);
    }

    function _fullyRestrictDex(
        address dex_,
        address token0_,
        address token1_
    ) internal {
        setBorrowProtocolLimitsPaused(dex_, token0_);
        setBorrowProtocolLimitsPaused(dex_, token1_);

        setSupplyProtocolLimitsPaused(dex_, token0_);
        setSupplyProtocolLimitsPaused(dex_, token1_);

        IFluidLiquidityWithdrawalLimit(address(LIQUIDITY))
            .updateUserWithdrawalLimit(dex_, token0_, type(uint256).max);
        IFluidLiquidityWithdrawalLimit(address(LIQUIDITY))
            .updateUserWithdrawalLimit(dex_, token1_, type(uint256).max);
    }

    /**
     * |
     * |     Payload Actions End Here      |
     * |__________________________________
     */

    // --- BEGIN AUTO-GENERATED PRICES (scripts/verify/prepare-prices.ts) ---
    // fetched: 2026-09-27, source: coingecko
    function ETH_USD_PRICE()    public pure override returns (uint256) { return 2_690 * 1e2; }
    function weETH_USD_PRICE()  public pure override returns (uint256) { return 2_970 * 1e2; }
    // --- END AUTO-GENERATED PRICES ---
}
