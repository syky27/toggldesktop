// Copyright 2014 Toggl Desktop developers.

#include "./aboutdialog.h"
#include "./ui_aboutdialog.h"

#include <QApplication>  // NOLINT

#include "./toggl.h"

AboutDialog::AboutDialog(QWidget *parent) : QDialog(parent),
ui(new Ui::AboutDialog) {
    ui->setupUi(this);

    ui->version->setText(QApplication::applicationVersion());
}

AboutDialog::~AboutDialog() {
    delete ui;
}
