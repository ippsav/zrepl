# zrepl

zrepl is a command-line interface application for searching and viewing code snippets using ripgrep.

## Features

- Fast code search using ripgrep
- Interactive file and result navigation
- Real-time search results
- Syntax highlighting for search matches

## Installation

To install zrepl, you need to have Zig installed on your system. Then, follow these steps:

1. Clone the repository
2. Navigate to the project directory
3. Run `zig build`

## Usage

To start the application, run:
```sh
zig-out/bin/zrepl
```

### Key Bindings

- `Tab`: Switch between search input and file list
- `j`: Move down in the file list
- `k`: Move up in the file list
- `Ctrl+C`: Exit the application

## Dependencies

zrepl relies on [libvaxis](https://github.com/rockorager/libvaxis) for terminal UI.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.