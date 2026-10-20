QT += core gui widgets qml quick quickcontrols2 dbus

CONFIG += c++17 release
TARGET = omatype
TEMPLATE = app

HEADERS += \
    src/backend.h \
    src/cli.h \
    src/systemtheme.h

SOURCES += \
    src/main.cpp \
    src/backend.cpp \
    src/cli.cpp \
    src/systemtheme.cpp

RESOURCES += src/resources.qrc
