// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title JURY
/// @notice A fixed-supply ERC-20. The whole supply is minted once, in the constructor, to the
///         deployer (`msg.sender`). There is no owner, no minter, no pause, no blocklist and no
///         transfer fee: after construction the contract has no privileged functions at all.
/// @dev    The Solidity identifier `JuryToken` is the launch manifest's `token.contract`; the
///         token's own name and symbol are what `name()` and `symbol()` return.
contract JuryToken is ERC20 {
    /// @notice The token name returned by `name()`.
    string public constant TOKEN_NAME = "JURY";

    /// @notice The token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "JURY";

    /// @notice Decimals of the token, as `decimals()` returns (the ERC20 default).
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @notice The whole supply in minor units: 1,000,000,000 tokens with 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(TOKEN_DECIMALS);

    /// @notice Mints `TOTAL_SUPPLY` to the deployer. Nothing can mint afterwards.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
