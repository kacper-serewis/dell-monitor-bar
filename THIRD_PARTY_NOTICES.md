# Acknowledgements and third-party notices

The Apple Silicon private API usage and display discovery in `DDCBridge.m`
were informed by [waydabber/m1ddc](https://github.com/waydabber/m1ddc), commit
`7339ceebb03f691b1eaeb8471dca301d215d19c8`. Its MIT notice is reproduced below.
This app implements its own exact-port service matching, packet validation and
command policy.

The Dell-specific KVM toggle (`VCP 0xE7 = 0xFF00`) and the distinctions between
an action, USB association map, and USB host state were informed by
[tatimblin/delldisplay](https://github.com/tatimblin/delldisplay), commit
`cda8f3f6a86070bcc7951bffab653ada46abe10f`, particularly `docs/kvm.md` and
`docs/PROTOCOL.md`. No compiled Dell libraries or installer resources are used
or distributed.

## m1ddc

MIT License

Copyright (c) 2021 waydabber

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
