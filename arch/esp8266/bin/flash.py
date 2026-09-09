import sys, os
from argparse import ArgumentParser, RawDescriptionHelpFormatter, ArgumentTypeError

START_ADDRESS   = 0x52000
LAYOUT_ADDRESS  = 0x51000
SECTOR_SIZE = 4096
MAX_LINE_LEN = max_line_len=128 - len(os.linesep)

class BlockNumber:
    @staticmethod
    def from_address(addr): return BlockNumber(addr // SECTOR_SIZE)
    def __init__(self, num): self.num = num
    def __str__(self): return str(self.num)

class App:
    TEMPLATE = """%s load
%s load
%s
stack-show
/end\n"""

    def __init__(self, path, address, layout_address, code_format):
        self.path = path
        self.address = address
        self.layout_address = layout_address
        self.code_format = code_format

    def _generate(self, core_block_num):
        name = 'main.tmp'
        with open(name, "wt") as f: f.write(self._content(core_block_num))
        return name

    def _content(self, core_block_num):
        return App.TEMPLATE % (core_block_num, BlockNumber.from_address(self.layout_address), self._read())

    def code(self):
        code = Code(self._generate('dummy'.ljust(8)), 'APP', self.code_format)
        core_block_num = BlockNumber.from_address(self.address + code.flash_usage()) # XXX Assumption: after me there is the core module
        return Code(self._generate(str(core_block_num).ljust(8)), 'APP', self.code_format) # save it again with the correct address

    def _read(self):
        if not self.path: return ''
        with open(self.path, "rt") as app: return app.read()

    def _save(self, output_file, content):
        with open(output_file, 'wt') as f: f.write(content)
        return output_file

class CodeFormat:
    @staticmethod
    def create(block_format):
        return ScreenAlignedFormat(MAX_LINE_LEN) if block_format else OriginalFormat()

    def transform(self, content): raise RuntimeError('Subclass responsibility')

class ScreenAlignedFormat(CodeFormat):
    def __init__(self, max_line_len):
        self.max_line_len = max_line_len

    def transform(self, content):
        """ This is for the block screen editor. A screen = 128 columns and 32 rows """
        def pad_line(line):
            return line + (' ' * (self.max_line_len - len(line)))
        return '\n'.join([pad_line(line) for line in content.split('\n')])

class OriginalFormat(CodeFormat):
    def transform(self, content): return content

class Code:
    def __init__(self, path, name, code_format):
        self.name = name
        self.content = code_format.transform(self._load(path))

    def _load(self, path):
        with open(path) as f: return f.read()

    def validate(self, max_line_len):
        if any(len(line) > max_line_len for line in self.content.split('\n')):
            raise RuntimeError('Input overflow at line: "%s"' % [line for line in self.content.split('\n') if len(line) >= max_line_len][0])
    
    def flash_usage(self):
        return (len(self.content) // SECTOR_SIZE + 1) * SECTOR_SIZE

    def flashable(self, address):
        return Flashable(self.name, address, self._save("%s.tmp" % self.name))

    def _save(self, output_file):
        with open(output_file, 'wt') as f: f.write(self.content)
        return output_file

class Flashable:
    def __init__(self, name, address, path):
        self.name = name
        self.address = address
        self.path = path

class Modules:
    class All:
        def __call__(self, code): return code.name.lower() != 'test'
        def __str__(self): return 'ALL'

    class Nothing:
        def __call__(self, code): return code.name.lower() == 'app'
        def __str__(self): return 'NONE'

    class Only:
        def __init__(self, names): 
            self.names = set(each.lower() for each in names)
            self.names.add('core')
            self.names.add('app')
            self.names.add('layout')
        def __call__(self, code): return code.name.lower() in self.names
        def __str__(self): return 'Only: %s' % self.names

    def __init__(self, start_address, layout_address, max_line_len):
        self.start_address = start_address
        self.layout_address = layout_address
        self.max_line_len = max_line_len
        self.modules = []
        self.module_filter = Modules.All()

    def add(self, code):
        code.validate(self.max_line_len)
        self.modules.append(code)
        return self

    def select(self, module_filter):
        print('Selected modules: %s' % module_filter)
        self.module_filter = module_filter
    
    def selected(self):
        return (each for each in self.modules if self.module_filter(each))

    def flash(self, esp, block_format):
        self.flash_layout(esp, block_format)
        self.flash_modules(esp, block_format)

    def flash_layout(self, esp, block_format):
        layout = Layout.generate(self.to_be_flashed(), block_format)
        if self.module_filter(layout):
            flashable = layout.flashable(self.layout_address)
            esp.write_flash(self.layout_address, flashable.path)

    def flash_modules(self, esp, block_format):
        esp.write_flash_many([(each.address, each.path) for each in self.to_be_flashed()])

    def to_be_flashed(self):
        result = []
        address = self.start_address
        for code in self.selected():
            result.append(code.flashable(address))
            address += code.flash_usage()
        return result
    
class Layout:
    @staticmethod
    def generate(flashables, block_format):
        layout = 'layout.tmp'
        with open(layout, 'wt') as f:
            for each in flashables:
                if each.name not in ['APP', 'CORE']:
                    f.write('%s constant: %s\n' % (BlockNumber.from_address(each.address), each.name))
            f.write('/end\n')
        return Code(layout, 'LAYOUT', CodeFormat.create(block_format))

class Binaries:
    def __init__(self):
        self.binaries = (
            (0x0000, 'rboot.bin'),
            (0x1000, 'blank_config.bin'),
            (0x2000, 'punyforth.bin'))

    def flash(self, esp):
        print("Flashing binaries..")
        esp.write_flash_many(self.binaries)
    
class Esp:
    def __init__(self, port, flashmode):
        self.port = port
        self.flashmode = flashmode

    def write_flash(self, address, path):
        print('Flashing %s' % os.path.basename(path))
        os.system("python esptool.py -p %s write_flash -fm %s -ff 40m 0x%x %s" % (self.port, self.flashmode, address, path))

    def write_flash_many(self, tupl):
        if not tupl: return
        print('Flashing %s' % ', '.join('0x%x: %s' % (address, os.path.basename(path)) for (address, path) in tupl))
        os.system("python esptool.py -p %s write_flash -fs 32m -fm %s -ff 40m %s" % (self.port, self.flashmode, ' '.join("0x%x %s" % each for each in tupl)))

class CommandLine:
    @staticmethod
    def to_bool(v):
        if v.lower() in ('yes', 'true', 'y', '1'): return True
        if v.lower() in ('no', 'false', 'n', '0'): return False
        raise ArgumentTypeError('%s is not a boolean' % v)

    def __init__(self):
        self.parser = ArgumentParser(description='Flash punyforth binaries and forth code.', epilog=self.examples(), formatter_class=RawDescriptionHelpFormatter)
        self.parser.add_argument('port', help='COM port of the esp8266')
        self.parser.add_argument('--modules', nargs='*', default=['all'], help='List of modules. Default is "all".')
        self.parser.add_argument('--binary', default=True, type=CommandLine.to_bool, help='Use "no" to skip flashing binaries. Default is "yes".')
        self.parser.add_argument('--main', default='', help='Path of the Forth code that will be used as an entry point.')
        self.parser.add_argument('--flashmode', default='qio', help='Valid values are: qio, qout, dio, dout')
        self.parser.add_argument('--block-format', default=False, type=CommandLine.to_bool, help='Use "yes" to format source code into block format (128 columns and 32 rows padded with spaces). Default is "no".')

    def examples(self):
        return """
Examples:
Flash only source code in block format. Only flash the "flash" module.
    $ python flash.py /dev/cu.wchusbserial1410 --binary false --block-format true --main myapp.forth --modules flash

Flash all modules and binaries:
    $ python flash.py /dev/cu.wchusbserial1410

Flash all modules, binaries and use myapp.forth as an entry point:
    $ python flash.py /dev/cu.wchusbserial1410 --main myapp.forth

Available modules:\n%s
        """ % '\n'.join("\t* %s" % each[1] for each in AVAILABLE_MODULES)
    
    def parse(self):
        args = self.parser.parse_args()
        args.modules = self.modules(args)
        args.code_format = CodeFormat.create(args.block_format)
        return args

    def modules(self, args):
        if args.modules == ['all']: return Modules.All()
        if args.modules == ['none']: return Modules.Nothing()
        return Modules.Only(args.modules)

# TODO:
# Protection against loading multiple transitive modules

AVAILABLE_MODULES = [
    ('../../../generic/forth/core.forth', 'CORE'),
    ('../forth/dht22.forth', 'DHT22'),
    ('../forth/flash.forth', 'FLASH'),
    ('../forth/font5x7.forth', 'FONT57'),
    ('../forth/gpio.forth', 'GPIO'),
    ('../forth/mailbox.forth', 'MAILBOX'),
    ('../forth/netcon.forth', 'NETCON'),
    ('../forth/ntp.forth', 'NTP'),
    ('../forth/ping.forth', 'PING'),
    ('../forth/sonoff.forth', 'SONOFF'),
    ('../forth/ssd1306-i2c.forth', 'SSD1306I2C'),
    ('../forth/ssd1306-spi.forth', 'SSD1306SPI'),
    ('../forth/tasks.forth', 'TASKS'),
    ('../forth/tcp-repl.forth', 'TCPREPL'),
    ('../forth/turnkey.forth', 'TURNKEY'),
    ('../forth/wifi.forth', 'WIFI'),
    ('../forth/event.forth', 'EVENT'),
    ('../../../generic/forth/ringbuf.forth', 'RINGBUF'),
    ('../../../generic/forth/decompiler.forth', 'DECOMP'),
    ('../../../generic/forth/punit.forth', 'PUNIT'),
    ('../../../generic/forth/test.forth', 'TEST')
]

def tmpfiles(): return (each for each in os.listdir('.') if each.endswith('.tmp'))
def remove(files):
    for each in files: os.remove(each)

if __name__ == '__main__':
    args = CommandLine().parse()
    esp = Esp(args.port, args.flashmode)
    app = App(args.main, START_ADDRESS, LAYOUT_ADDRESS, args.code_format)
    modules = Modules(START_ADDRESS, LAYOUT_ADDRESS, max_line_len=MAX_LINE_LEN)
    modules.add(app.code())
    for path, name in AVAILABLE_MODULES: modules.add(Code(path, name, args.code_format))
    modules.select(args.modules)
    if args.binary: Binaries().flash(esp)
    modules.flash(esp, args.block_format)
    remove(tmpfiles())
