// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import "ds-test/test.sol";

import {YieldLadle, YieldLever} from "../YieldLev.sol";

interface VM {
    function prank(address sender) external;
    function warp(uint timestamp) external;
    function roll(uint blockNumber) external;
}

interface YieldPool {
    function getCache() external returns (uint112, uint112, uint32);
}

interface YieldCauldron {
    function balances(bytes12) external returns (uint128, uint128);
}

interface yVaultEx {
  function deposit(uint amount) external returns (uint);
  function withdraw() external returns (uint);

  function withdrawalQueue(uint index) external returns (address);
}

interface yStrategy {
    function keeper() external view returns (address);
    function name() external view returns (string memory);
    function harvest() external;
}

interface IUSDC {
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    // admin
    function masterMinter() external returns(address);
    function configureMinter(address minter, uint256 minterAllowedAmount) external returns (bool);
    function mint(address _to, uint256 _amount) external returns (bool);
}


contract ContractTest is DSTest {
    IUSDC constant _usdc = IUSDC(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    VM constant _vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    yVaultEx constant yvUSDC = yVaultEx(0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE);

    YieldLadle _ladle;
    YieldLever _lever;
    YieldPool _pool;

    uint constant baseAmount = 250 * 1e3 * 1e6; // 250k USDC
    uint constant borrowAmount = 750 * 1e3 * 1e6; // 750k USDC
    uint constant maxFyAmount = borrowAmount + 7 * 1e3 * 1e6; // borrowAmount + 7k
    bytes6 seriesId = 0x303230350000; // FYUSDC05LP

    bytes12 vaultId; // computed in setUp()
    int128 inkAmount;


    function setUp() public {
        _vm.prank(_usdc.masterMinter());
        _usdc.configureMinter(address(this), baseAmount); // 250k USDC
        _usdc.mint(address(this), baseAmount);

        _ladle = YieldLadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
        _lever = new YieldLever(_ladle);
        
        _usdc.approve(address(_lever), baseAmount);

        uint8 salt = 0;
        vaultId = bytes12(keccak256(abi.encodePacked(address(_lever), block.timestamp, salt)));
        _pool = YieldPool(_ladle.pools(seriesId));

        (, uint112 fyTokens,) = _pool.getCache();
        _lever.invest(baseAmount, borrowAmount, maxFyAmount, seriesId);
        (, uint112 fyTokens2,) = _pool.getCache();
        inkAmount = int128(uint128(fyTokens)) - int128(uint128(fyTokens2));
    }

    /**
    @dev Attempts to harvest the yearn vault, so that it generates profit
    In reality, profit in its strategies comes from external services (lending on
    AAVE, Sushi, Balancer), so without simulating activity there the vault
    has no profits and actually loses money
     */
    function yvHarvest() internal {
        emit log_string("yvHarvest");
        for (uint i = 0; i < 20; ++i) {
            yStrategy strategy = yStrategy(yvUSDC.withdrawalQueue(i));
            if (address(strategy) == address(0)) {
                break;
            }
            emit log_named_string("\tstrategy", strategy.name());
            _vm.prank(strategy.keeper());
            (bool success, bytes memory returnData) = address(strategy).call(
                abi.encodeWithSignature(
                    "harvest()"
                )
            );
            if (success) {
                emit log_string("\tsuccess");
            } else {
                emit log_string("\tfailure");
            }
        }
    }

    function computeStats() internal {
        (uint128 debt, uint128 collateral) = YieldCauldron(_ladle.cauldron()).balances(vaultId);
        assertEq(debt, 0);
        uint256 balance = _usdc.balanceOf(address(this)) + collateral;
        emit log_named_uint("collateral in vault", collateral / 1e6);
        emit log_named_uint("collateral in wallet", (balance - collateral) / 1e6);
        emit log_named_int("profit", (int256(balance) - int256(baseAmount)) / 1e6);
    }

    function testImmediateWithdraw() public {
        yvHarvest();
        _lever.unwind(vaultId, maxFyAmount, _ladle.pools(seriesId), inkAmount);
        computeStats();
    }

    function testWithdrawIn1Week() public {
        _vm.roll(block.number + 1);
        _vm.warp(block.timestamp + 3600 * 24 * 7);
        yvHarvest();
        _lever.unwind(vaultId, maxFyAmount, _ladle.pools(seriesId), inkAmount);
        computeStats();
    }

    function testWithdrawIn2Months() public {
        _vm.roll(block.number + 1);
        _vm.warp(block.timestamp + 3600 * 24 * 30 * 2);
        yvHarvest();
        _lever.unwind(vaultId, maxFyAmount, _ladle.pools(seriesId), inkAmount);
        computeStats();
    }

    function testWithdrawIn1Year() public {
        _vm.roll(block.number + 1);
        _vm.warp(block.timestamp + 3600 * 24 * 365);
        yvHarvest();
        _lever.unwind(vaultId, maxFyAmount, _ladle.pools(seriesId), inkAmount);
        computeStats();
    }

}
