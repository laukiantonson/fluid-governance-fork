// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.21;
pragma experimental ABIEncoderV2;

import {PayloadIGPPriceHelpers} from "../common/pricehelpers.sol";
import {
    AdminModuleStructs as FluidLiquidityAdminStructs
} from "../common/interfaces/IFluidLiquidity.sol";

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

    function execute() public virtual override {
        super.execute();

        // Action 1: Fully restrict the dexV1 test DEX at the Liquidity Layer.
        action1();

        // Action 2: Rebalance vault 3 (wstETH/ETH) and restore its dust limit.
        action2();

        // Action 3: Raise weETH/ETH vault (182) to launch limits.
        action3();
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
