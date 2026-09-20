cmake_minimum_required(VERSION 3.21)

set(MORIXTERM_VERSION "3" CACHE STRING "MoriXterm version")
project(MoriXterm VERSION ${MORIXTERM_VERSION} LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

find_package(Qt6 6.4 REQUIRED COMPONENTS Quick QuickControls2 Gui Sql)
qt_standard_project_setup(REQUIRES 6.4)

qt_add_executable(morixtrem
    src/main.cpp
    src/PtyProcess.cpp src/PtyProcess.h
    src/TerminalItem.cpp src/TerminalItem.h
    src/FileEntryModel.cpp src/FileEntryModel.h
    src/FileManagerController.cpp src/FileManagerController.h
    src/FtpClientController.cpp src/FtpClientController.h
    src/AppLockManager.cpp src/AppLockManager.h
    src/RdpSessionController.cpp src/RdpSessionController.h
    src/SessionStore.cpp src/SessionStore.h
    src/CredentialStore.cpp src/CredentialStore.h
    src/SshSecurity.cpp src/SshSecurity.h
    src/SecurityHardening.cpp src/SecurityHardening.h
)


if(WIN32)
    configure_file(packaging/windows/morixtrem.rc.in ${CMAKE_CURRENT_BINARY_DIR}/morixtrem.rc @ONLY)
    target_sources(morixtrem PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/morixtrem.rc)
endif()

qt_add_resources(morixtrem morixtrem_resources
    PREFIX "/"
    FILES
        qml/Main.qml
        qml/components/MButton.qml
        qml/components/MIconButton.qml
        qml/components/MTextField.qml
        qml/components/MComboBox.qml
        qml/components/MCheckBox.qml
        qml/components/MContextItem.qml
        qml/components/MTopToolButton.qml
        qml/components/MVectorIcon.qml
        qml/components/MToastHost.qml
        qml/components/FtpWorkspace.qml
        assets/morixtrem-brand.png
        assets/morixtrem-app.png
        assets/morixtrem.png
        assets/icons/folder.svg
        assets/icons/file.svg
        assets/icons/archive.svg
)

target_link_libraries(morixtrem PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Gui
    Qt6::Sql
)

if(UNIX AND NOT APPLE)
    target_link_libraries(morixtrem PRIVATE util)
endif()

if(WIN32)
    target_link_libraries(morixtrem PRIVATE Advapi32)
    set_target_properties(morixtrem PROPERTIES WIN32_EXECUTABLE TRUE)
endif()

include(GNUInstallDirs)
install(TARGETS morixtrem
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
install(FILES assets/morixtrem.png DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/256x256/apps RENAME morixtrem.png)
install(FILES packaging/linux/morixtrem.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)

set(CPACK_PACKAGE_NAME "MoriXterm")
set(CPACK_PACKAGE_VENDOR "mortenaho")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Secure SSH, RDP and terminal workspace")
set(CPACK_PACKAGE_CONTACT "mortenaho")
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "mortenaho")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "openssh-client, curl, libsecret-tools, sshpass, zip, unzip, freerdp3-x11 | freerdp-x11, libqt6svg6, libqt6sql6-sqlite, qml6-module-qtquick, qml6-module-qtquick-controls, qml6-module-qtquick-dialogs, qml6-module-qtquick-layouts")
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
set(CPACK_PACKAGE_FILE_NAME "MoriXterm-${PROJECT_VERSION}-${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}")
include(CPack)

include(CTest)
if(BUILD_TESTING AND UNIX AND NOT APPLE)
    find_package(Qt6 6.4 REQUIRED COMPONENTS Test)
    qt_add_executable(rdp_session_test
        tests/RdpSessionControllerTest.cpp
        src/RdpSessionController.cpp src/RdpSessionController.h
    )
    target_link_libraries(rdp_session_test PRIVATE Qt6::Test Qt6::Gui)
    add_test(NAME rdp_session_test COMMAND rdp_session_test)
    set_tests_properties(rdp_session_test PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
