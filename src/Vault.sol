// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    error Vault__RedeemFailed();

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {
        // Allow the contract to receive Ether
    }

    /**
     * @notice Deposit Ether into the vault and mint corresponding rebase tokens.
     * @dev This function allows users to deposit Ether, which will be converted to rebase tokens.
     */
    function deposit() external payable {
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeem rebase tokens for Ether.
     * @param _amount The amount of rebase tokens to redeem.
     * @dev This function allows users to redeem their rebase tokens for Ether.
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}(""); // Transfer the Ether back to the user
        if (!success) {
            revert Vault__RedeemFailed();
        }
    }

    /**
     * @notice Get the address of the rebase token associated with this vault.
     * @return The address of the rebase token.
     * @dev This function allows external contracts to retrieve the rebase token address for interactions.
     */
    function getRebaseToken() external view returns (address) {
        // Returns the address of the rebase token associated with this vault
        return address(i_rebaseToken);
    }
}
