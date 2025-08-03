// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author vk1033
 * @notice This is a cross-chain rebase token that incentivizes users to deposit into a vault and gain interest in return.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error Rebase__InterestCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18; // Precision factor for interest calculations
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE"); // Role for minting and burning tokens
    uint256 private s_interestRate = 5e10; // Interest rate for the rebase token
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userlastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        // Grant the mint and burn role to an account
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate for the rebase token.
     * @param _newInterestRate The new interest rate to be set.
     * @dev This function allows the owner to set a new interest rate, but it can only decrease the current interest rate.
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Logic to set the new interest rate
        if (_newInterestRate > s_interestRate) {
            revert Rebase__InterestCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;

        emit InterestRateSet(s_interestRate);
    }

    /**
     * @notice Get the principle balance of a user.
     * @param _user The address of the user to check the balance for.
     * @return The principal balance of the user without accrued interest.
     * @dev This function returns the balance of the user without considering any accrued interest.
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        // Returns the principal balance of the user without accrued interest
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint new tokens to a specified address.
     * @param _to The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     * @dev This function mints new tokens and updates the user's interest rate and last updated timestamp.
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn tokens from a specified address.
     * @param _from The address to burn tokens from.
     * @param _amount The amount of tokens to burn.
     * @dev This function burns tokens and updates the user's accrued interest.
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Get the balance of a user, including accrued interest.
     * @param _user The address of the user to check the balance for.
     * @return The balance of the user, including accrued interest.
     * @dev This function overrides the balanceOf function to include accrued interest since the last update.
     * The interest is calculated based on the time elapsed since the last update and the user's interest rate.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // Calculate the balance considering accrued interest
        return super.balanceOf(_user) + _calculateAccruedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens to a recipient, updating accrued interest for both sender and recipient.
     * @param _recipent The address of the recipient.
     * @param _amount The amount of tokens to transfer.
     * @return True if the transfer was successful.
     * @dev This function overrides the transfer function to ensure that accrued interest is updated for both the sender and recipient.
     */
    function transfer(address _recipent, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipent);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipent) == 0) {
            s_userInterestRate[_recipent] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipent, _amount);
    }

    /**
     * @notice Transfer tokens from one address to another, updating accrued interest for both sender and recipient.
     * @param _sender The address of the sender.
     * @param _recipient The address of the recipient.
     * @param _amount The amount of tokens to transfer.
     * @return True if the transfer was successful.
     * @dev This function overrides the transferFrom function to ensure that accrued interest is updated for both the sender and recipient.
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculate the accrued interest for a user since their last update.
     * @param _user The address of the user to calculate interest for.
     * @return linearInterest The amount of interest accrued since the last update.
     * @dev This function calculates the interest based on the user's interest rate and the time elapsed since their last update.
     */
    function _calculateAccruedInterestSinceLastUpdate(address _user) internal view returns (uint256 linearInterest) {
        uint256 timeElapsed = block.timestamp - s_userlastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    /**
     * @notice Mint accrued interest for a user.
     * @param _user The address of the user to mint interest for.
     * @dev This function mints the accrued interest for the user based on their last updated timestamp and current balance.
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;

        s_userlastUpdatedTimestamp[_user] = block.timestamp;

        _mint(_user, balanceIncrease);
    }

    /**
     * @notice Get the current interest rate for the rebase token.
     * @return The current interest rate.
     * @dev This function returns the current interest rate for the rebase token.
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Get the interest rate for a specific user.
     * @param _user The address of the user to check the interest rate for.
     * @return The interest rate for the specified user.
     * @dev This function returns the interest rate for a specific user, which may differ from the global interest rate.
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
