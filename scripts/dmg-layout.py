"""Set Finder's initial layout without requesting Finder automation permission."""
from pathlib import Path
import sys
from ds_store import DSStore

stage = Path(sys.argv[1])
with DSStore.open(str(stage / '.DS_Store'), 'w+') as store:
    store['.']['bwsp'] = {
        'ShowStatusBar': False, 'ShowToolbar': False, 'ShowTabView': False,
        'ShowPathbar': False, 'ShowSidebar': False, 'ContainerShowSidebar': False,
        'WindowBounds': '{{180, 160}, {640, 440}}', 'SidebarWidth': 0,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 1,
        'backgroundColorRed': 0.985, 'backgroundColorGreen': 0.965, 'backgroundColorBlue': 0.95,
        'iconSize': 112.0, 'textSize': 15.0, 'gridSpacing': 100.0,
        'gridOffsetX': 0.0, 'gridOffsetY': 0.0, 'labelOnBottom': True,
        'showItemInfo': False, 'showIconPreview': True, 'arrangeBy': 'none',
    }
    store['.']['vSrn'] = ('long', 1)
    store['.']['icvl'] = ('type', b'icnv')
    store['Точка.app']['Iloc'] = (160, 160)
    store['Программы']['Iloc'] = (480, 160)
    store['Начни здесь.html']['Iloc'] = (320, 330)
