# Aderyn Analysis Report

This report was generated by [Aderyn](https://github.com/Cyfrin/aderyn), a static analysis tool built by [Cyfrin](https://cyfrin.io), a blockchain security company. This report is not a substitute for manual audit or security review. It should not be relied upon for any purpose other than to assist in the identification of potential security vulnerabilities.
# Table of Contents

- [Summary](#summary)
  - [Files Summary](#files-summary)
  - [Files Details](#files-details)
  - [Issue Summary](#issue-summary)
- [Low Issues](#low-issues)
  - [L-1: Centralization Risk for trusted owners](#l-1-centralization-risk-for-trusted-owners)
  - [L-2: Solidity pragma should be specific, not wide](#l-2-solidity-pragma-should-be-specific-not-wide)
  - [L-3: `public` functions not used internally could be marked `external`](#l-3-public-functions-not-used-internally-could-be-marked-external)
  - [L-4: Define and use `constant` variables instead of using literals](#l-4-define-and-use-constant-variables-instead-of-using-literals)
  - [L-5: Event is missing `indexed` fields](#l-5-event-is-missing-indexed-fields)
  - [L-6: PUSH0 is not supported by all chains](#l-6-push0-is-not-supported-by-all-chains)
  - [L-7: State variable changes but no event is emitted.](#l-7-state-variable-changes-but-no-event-is-emitted)


# Summary

## Files Summary

| Key | Value |
| --- | --- |
| .sol Files | 3 |
| Total nSLOC | 359 |


## Files Details

| Filepath | nSLOC |
| --- | --- |
| src/Counter.sol | 10 |
| src/RockPaperScissors.sol | 335 |
| src/WinningToken.sol | 14 |
| **Total** | **359** |


## Issue Summary

| Category | No. of Issues |
| --- | --- |
| High | 0 |
| Low | 7 |


# Low Issues

## L-1: Centralization Risk for trusted owners

Contracts have owners with privileged rights to perform admin tasks and need to be trusted to not perform malicious updates or drain funds.

<details><summary>2 Found Instances</summary>


- Found in src/WinningToken.sol [Line: 13](src/WinningToken.sol#L13)

	```solidity
	contract WinningToken is ERC20, ERC20Burnable, Ownable {
	```

- Found in src/WinningToken.sol [Line: 34](src/WinningToken.sol#L34)

	```solidity
	    function mint(address to, uint256 amount) external onlyOwner {
	```

</details>



## L-2: Solidity pragma should be specific, not wide

Consider using a specific version of Solidity in your contracts instead of a wide version. For example, instead of `pragma solidity ^0.8.0;`, use `pragma solidity 0.8.0;`

<details><summary>3 Found Instances</summary>


- Found in src/Counter.sol [Line: 2](src/Counter.sol#L2)

	```solidity
	pragma solidity ^0.8.13;
	```

- Found in src/RockPaperScissors.sol [Line: 2](src/RockPaperScissors.sol#L2)

	```solidity
	pragma solidity ^0.8.13; // a: limit to single version
	```

- Found in src/WinningToken.sol [Line: 2](src/WinningToken.sol#L2)

	```solidity
	pragma solidity ^0.8.13;
	```

</details>



## L-3: `public` functions not used internally could be marked `external`

Instead of marking a function as `public`, consider marking it as `external` if it is not used internally.

<details><summary>4 Found Instances</summary>


- Found in src/Counter.sol [Line: 7](src/Counter.sol#L7)

	```solidity
	    function setNumber(uint256 newNumber) public {
	```

- Found in src/Counter.sol [Line: 11](src/Counter.sol#L11)

	```solidity
	    function increment() public {
	```

- Found in src/RockPaperScissors.sol [Line: 378](src/RockPaperScissors.sol#L378)

	```solidity
	    function tokenOwner() public view returns (address) {
	```

- Found in src/WinningToken.sol [Line: 25](src/WinningToken.sol#L25)

	```solidity
	    function decimals() public view virtual override returns (uint8) {
	```

</details>



## L-4: Define and use `constant` variables instead of using literals

If the same constant literal value is used multiple times, create a constant state variable and reference it throughout the contract.

<details><summary>4 Found Instances</summary>


- Found in src/RockPaperScissors.sol [Line: 100](src/RockPaperScissors.sol#L100)

	```solidity
	        require(_timeoutInterval >= 5 minutes, "Timeout must be at least 5 minutes");
	```

- Found in src/RockPaperScissors.sol [Line: 128](src/RockPaperScissors.sol#L128)

	```solidity
	        require(_timeoutInterval >= 5 minutes, "Timeout must be at least 5 minutes");
	```

- Found in src/RockPaperScissors.sol [Line: 484](src/RockPaperScissors.sol#L484)

	```solidity
	            uint256 fee = (totalPot * PROTOCOL_FEE_PERCENT) / 100;
	```

- Found in src/RockPaperScissors.sol [Line: 522](src/RockPaperScissors.sol#L522)

	```solidity
	            uint256 fee = (totalPot * PROTOCOL_FEE_PERCENT) / 100;
	```

</details>



## L-5: Event is missing `indexed` fields

Index event fields make the field more quickly accessible to off-chain tools that parse events. However, note that each index field costs extra gas during emission, so it's not necessarily best to index the maximum allowed per event (three fields). Each event should use three indexed fields if there are three or more fields, and gas usage is not particularly of concern for the events in question. If there are fewer than three fields, all of the fields should be indexed.

<details><summary>8 Found Instances</summary>


- Found in src/RockPaperScissors.sol [Line: 72](src/RockPaperScissors.sol#L72)

	```solidity
	    event GameCreated(uint256 indexed gameId, address indexed creator, uint256 bet, uint256 totalTurns);
	```

- Found in src/RockPaperScissors.sol [Line: 74](src/RockPaperScissors.sol#L74)

	```solidity
	    event MoveCommitted(uint256 indexed gameId, address indexed player, uint256 currentTurn);
	```

- Found in src/RockPaperScissors.sol [Line: 75](src/RockPaperScissors.sol#L75)

	```solidity
	    event MoveRevealed(uint256 indexed gameId, address indexed player, Move move, uint256 currentTurn);
	```

- Found in src/RockPaperScissors.sol [Line: 76](src/RockPaperScissors.sol#L76)

	```solidity
	    event TurnCompleted(uint256 indexed gameId, address winner, uint256 currentTurn);
	```

- Found in src/RockPaperScissors.sol [Line: 77](src/RockPaperScissors.sol#L77)

	```solidity
	    event GameFinished(uint256 indexed gameId, address winner, uint256 prize);
	```

- Found in src/RockPaperScissors.sol [Line: 79](src/RockPaperScissors.sol#L79)

	```solidity
	    event JoinTimeoutUpdated(uint256 oldTimeout, uint256 newTimeout);
	```

- Found in src/RockPaperScissors.sol [Line: 80](src/RockPaperScissors.sol#L80)

	```solidity
	    event FeeCollected(uint256 gameId, uint256 feeAmount);
	```

- Found in src/RockPaperScissors.sol [Line: 81](src/RockPaperScissors.sol#L81)

	```solidity
	    event FeeWithdrawn(address indexed admin, uint256 amount);
	```

</details>



## L-6: PUSH0 is not supported by all chains

Solc compiler version 0.8.20 switches the default target EVM version to Shanghai, which means that the generated bytecode will include PUSH0 opcodes. Be sure to select the appropriate EVM version in case you intend to deploy on a chain other than mainnet like L2 chains that may not support PUSH0, otherwise deployment of your contracts will fail.

<details><summary>3 Found Instances</summary>


- Found in src/Counter.sol [Line: 2](src/Counter.sol#L2)

	```solidity
	pragma solidity ^0.8.13;
	```

- Found in src/RockPaperScissors.sol [Line: 2](src/RockPaperScissors.sol#L2)

	```solidity
	pragma solidity ^0.8.13; // a: limit to single version
	```

- Found in src/WinningToken.sol [Line: 2](src/WinningToken.sol#L2)

	```solidity
	pragma solidity ^0.8.13;
	```

</details>



## L-7: State variable changes but no event is emitted.

State variable changes in this function but no event is emitted.

<details><summary>3 Found Instances</summary>


- Found in src/Counter.sol [Line: 7](src/Counter.sol#L7)

	```solidity
	    function setNumber(uint256 newNumber) public {
	```

- Found in src/Counter.sol [Line: 11](src/Counter.sol#L11)

	```solidity
	    function increment() public {
	```

- Found in src/RockPaperScissors.sol [Line: 386](src/RockPaperScissors.sol#L386)

	```solidity
	    function setAdmin(address _newAdmin) external {
	```

</details>



