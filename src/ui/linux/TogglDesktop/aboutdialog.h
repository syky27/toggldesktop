// Copyright 2014 Toggl Desktop developers.

#ifndef SRC_UI_LINUX_TOGGLDESKTOP_ABOUTDIALOG_H_
#define SRC_UI_LINUX_TOGGLDESKTOP_ABOUTDIALOG_H_

#include <QDialog>

namespace Ui {
class AboutDialog;
}

class AboutDialog : public QDialog {
    Q_OBJECT

 public:
    explicit AboutDialog(QWidget *parent = 0);
    ~AboutDialog();

 private:
    Ui::AboutDialog *ui;
};

#endif  // SRC_UI_LINUX_TOGGLDESKTOP_ABOUTDIALOG_H_
