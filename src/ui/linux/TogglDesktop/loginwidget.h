// Copyright 2014 Toggl Desktop developers.

#ifndef SRC_UI_LINUX_TOGGLDESKTOP_LOGINWIDGET_H_
#define SRC_UI_LINUX_TOGGLDESKTOP_LOGINWIDGET_H_

#include <QWidget>
#include <QStackedWidget>

#include <stdint.h>

#include "./timeentryview.h"

namespace Ui {
class LoginWidget;
}

class LoginWidget : public QWidget {
    Q_OBJECT

 public:
    explicit LoginWidget(QStackedWidget *parent = nullptr);
    ~LoginWidget();

    void display();

 protected:
    virtual void keyPressEvent(QKeyEvent *event);
    void mousePressEvent(QMouseEvent *event);

 private slots:  // NOLINT
    void on_login_clicked();

    void displayLogin(
        const bool open,
        const uint64_t user_id);

    void displayError(
        const QString errmsg,
        const bool user_error);

 private:
    Ui::LoginWidget *ui;

    bool validateFields();
    void enableAllControls(const bool enable);
};

#endif  // SRC_UI_LINUX_TOGGLDESKTOP_LOGINWIDGET_H_
