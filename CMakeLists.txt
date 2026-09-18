cmake_minimum_required(VERSION 3.21)

project(MoriXterm VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(morixterm
    src/main.cpp
    src/connectionmanager.cpp
    src/connectionmanager.h
    src/sessionmodel.cpp
    src/sessionmodel.h
)

qt_add_qml_module(morixterm
    URI MoriXterm
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/SessionDialog.qml
        qml/components/Toast.qml
)

target_link_libraries(morixterm
    PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
)

set_target_properties(morixterm PROPERTIES
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

include(GNUInstallDirs)
install(TARGETS morixterm
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
