# ivuorinen/homebrew-tap

A Homebrew tap for ivuorinen's custom formulae with automated documentation and dark mode support.

## Quick Start

```bash
# Add the tap
brew tap ivuorinen/homebrew-tap

# Install a formula
brew install <formula-name>

# List available formulae
brew search ivuorinen/homebrew-tap/
```

## Documentation

Visit [https://ivuorinen.net/homebrew-tap/](https://ivuorinen.net/homebrew-tap/) for complete documentation with:
- Installation instructions for each formula
- Dependencies and version information
- Source links and SHA256 checksums
- Dark mode support with system preference detection

## Contributing

1. Fork this repository
2. Create a new formula in the `Formula/` directory following the [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
3. Submit a pull request

The CI will automatically validate your formula and update the documentation site.

## Development

This tap uses a custom Ruby-based static site generator with zero external dependencies.

### Quick Start

For new contributors or first-time setup:

```bash
make setup    # Install Ruby dependencies and set up the environment
make build    # Build the documentation site
make serve    # Start development server
```

Or use the all-in-one development command:

```bash
make dev      # Full workflow: parse formulae, build site, and start server
```

### Commands

#### Using Make (Recommended)

The project includes a comprehensive Makefile that provides convenient commands for all build operations:

```bash
make help     # Show all available commands with descriptions
make build    # Build the documentation site
make serve    # Start development server (http://localhost:4000)
make parse    # Parse formulae and generate JSON data only
make clean    # Clean all generated files
```

**Development workflow:**
```bash
make setup          # Initial setup: install Ruby dependencies and bundler
make dev            # Full development workflow (parse + build + serve)
make test           # Run validation tests
make check          # Check project structure
make install        # Install Ruby dependencies (if Gemfile exists)
make info           # Show project information
```

**Server options:**
```bash
make serve PORT=3000              # Use port 3000
make serve HOST=0.0.0.0          # Bind to all interfaces
make serve PORT=8080 HOST=0.0.0.0 # Custom port and host
make serve-all                   # Start server on all interfaces (0.0.0.0)
make serve-3000                  # Quick shortcut for port 3000
make watch                       # Alias for serve with auto-rebuild
```

**Homebrew-specific targets:**
```bash
make tap-test                    # Test tap installation locally
make tap-install                 # Install this tap locally
make formula-new NAME=tool-name  # Create new formula template
```

**Production and testing:**
```bash
make build-production  # Clean build for production deployment
make version          # Show version information
```

All Makefile targets include helpful status messages and error handling.

**File Watching and Auto-Rebuild:**

The development server (`make serve`) includes intelligent file watching that:
- ✅ Only watches source files (Formula/, theme/, scripts/, config files)
- ✅ Excludes generated output files to prevent infinite rebuild loops
- ✅ Includes debouncing to handle multiple rapid file changes
- ✅ Provides clear status messages for rebuild operations

Files monitored for changes:
- `Formula/**/*.rb` - Homebrew formula files
- `theme/**/*.{css,js,erb,html}` - Theme templates and assets
- `scripts/*.rb` - Build scripts
- `Makefile`, `README.md`, `Gemfile` - Configuration files

#### Using Ruby Scripts (Alternative)

```bash
ruby scripts/make.rb build    # Build the documentation site
ruby scripts/make.rb serve    # Start development server
ruby scripts/make.rb parse    # Parse formulae and generate JSON data only
ruby scripts/make.rb clean    # Clean all generated files
ruby scripts/make.rb help     # Show all available commands
```

### How It Works

The documentation system consists of three main components:

1. **Formula Parser** - Safely extracts metadata from `.rb` files using regex patterns (no code evaluation)
2. **Site Builder** - Generates static HTML from ERB templates using the parsed data
3. **Development Server** - Serves the site locally with auto-rebuild on file changes

### Project Structure

```
docs/
├── _data/                  # Generated JSON data
├── assets/                 # Copied static assets (fonts, images, etc.)
├── formula/                # Individual formula pages (generated)
├── index.html              # Homepage (generated)
└── formulae.html           # Formula listing (generated)
theme/
├── assets/                 # Original assets: fonts, images, etc.
├── _command_input.html.erb # Input command snippet partial
├── _footer.html.erb        # Footer partial
├── _formula_card.html.erb  # Formula card partial
├── _head.html.erb          # HTML head partial
├── _header.html.erb        # Header partial
├── _nav.html.erb           # Navigation partial
├── _nothing_here.html.erb  # "No formulae found" partial
├── index.html.erb          # Homepage template
├── formulae.html.erb       # Formula listing template
├── formula.html.erb        # Individual formula template
├── style.css               # Stylesheets with dark mode support
└── main.js                 # Site functionality: search, dark mode toggle, etc.
Formula/
└── *.rb                    # Homebrew formula files
scripts/
├── make.rb                 # Main build script
└── parser.rb               # Formula parser
Makefile                    # Build commands and targets
README.md                   # This documentation
Gemfile                     # Ruby dependencies
```

### Features

- ✅ Zero external dependencies (Ruby stdlib only)
- ✅ Fast builds with auto-reload development server
- ✅ Dark mode with system preference detection
- ✅ Responsive design with accessibility support
- ✅ GitHub Pages compatible output
- ✅ Automatic deployment via GitHub Actions

### Customization

Templates can be customized by editing files in the `theme/` directory:
- `index.html.erb` - Homepage template
- `formulae.html.erb` - Formula listing page
- `formula.html.erb` - Individual formula page template
- `style.css` - Stylesheets and theming
- `main.js` - JavaScript functionality

## License

This tap is released under the MIT License. See LICENSE for details.
