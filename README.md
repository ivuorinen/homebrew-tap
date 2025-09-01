# ivuorinen/homebrew-tap

A Homebrew tap for ivuorinen's custom formulae with automated documentation.

## Usage

```bash
# Add the tap
brew tap ivuorinen/homebrew-tap

# Install a formula
brew install <formula-name>

# List available formulae
brew search ivuorinen/homebrew-tap/
```

## Documentation

Visit [https://ivuorinen.github.io/homebrew-tap/](https://ivuorinen.github.io/homebrew-tap/) for complete documentation of all available formulae.

## Available Formulae

The documentation is automatically generated from the formula files and includes:
- Installation instructions
- Dependencies
- Version information
- Source links

## Contributing

1. Fork this repository
2. Create a new formula in the `Formula/` directory
3. Follow the [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
4. Submit a pull request

The CI will automatically validate your formula and update the documentation.

## Development

```bash
# Install dependencies
bundle install

# Parse formulae locally
ruby scripts/parse_formulas.rb

# Serve documentation locally
cd docs && bundle exec jekyll serve
```

## License

This tap is released under the MIT License. See LICENSE for details.
