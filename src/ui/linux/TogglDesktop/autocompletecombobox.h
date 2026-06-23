#ifndef AUTOCOMPLETECOMBOBOX_H
#define AUTOCOMPLETECOMBOBOX_H

#include <QComboBox>
#include <QLineEdit>
#include <QCompleter>
#include <QSortFilterProxyModel>
#include <QTimer>
#include <QVector>

#include "autocompleteview.h"

class AutocompleteCompleter;
class AutocompleteProxyModel;
class AutocompleteListView;

class AutocompleteComboBox : public QComboBox {
    Q_OBJECT
public:
    AutocompleteComboBox(QWidget *parent = nullptr);

    void setModel(QAbstractItemModel *model);

    void showPopup() override;

    bool eventFilter(QObject *o, QEvent *e) override;

    AutocompleteView *currentView();

    // Opt in to live Redmine issue search on this box (off by default; enabled
    // for the description/issue fields, not e.g. the new-project box).
    void setLiveSearchEnabled(bool enabled);

    // Replace the dropdown's items while the field is focused (i.e. mid-typing),
    // preserving the user's edit text and cursor. Used to surface live-search
    // results without the clear()/setEditText() churn the unfocused path uses.
    void refreshKeepingEdit(QVector<AutocompleteView *> list);

protected:
    void keyPressEvent(QKeyEvent *event) override;

private slots:
    void onDropdownVisibleChanged();
    void onDropdownSelected(AutocompleteView *item);

    void cancelSelection();

    void onTextEdited(const QString &text);
    void onSearchTimerTimeout();

signals:
    void returnPressed();
    void timeEntrySelected(const QString &name);
    void projectSelected(const QString &projectName, uint64_t projectId, const QString &color, const QString &taskName, uint64_t taskId);
    void billableChanged(bool billable);
    void tagsChanged(const QString &tags);

private:
    AutocompleteCompleter *completer;
    AutocompleteProxyModel *proxyModel;
    AutocompleteListView *listView;

    QTimer *searchTimer = nullptr;
    QString pendingSearchText;
    bool liveSearchEnabled = false;
    bool suppressSearch = false;  // set while text is changed programmatically
};

class AutocompleteCompleter : public QCompleter {
    Q_OBJECT
    friend class AutocompleteComboBox;
public:
    AutocompleteCompleter(QWidget *parent = nullptr);

    bool eventFilter(QObject *o, QEvent *e) override;
};

class AutocompleteProxyModel : public QSortFilterProxyModel {
    Q_OBJECT
    friend class AutocompleteComboBox;
public:
    AutocompleteProxyModel(QObject *parent = nullptr);

    bool filterAcceptsRow(int source_row, const QModelIndex &source_parent) const override;
};

#endif // AUTOCOMPLETECOMBOBOX_H
