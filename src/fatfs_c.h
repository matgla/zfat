// Zig 0.17 removed the @cImport builtin; this header carries the include list
// that used to live at the top of fatfs.zig and is fed to a b.addTranslateC step.
#include <ff.h>
#include <diskio.h>
