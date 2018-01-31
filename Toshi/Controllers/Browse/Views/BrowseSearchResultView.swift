// Copyright (c) 2018 Token Browser, Inc
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import Foundation
import SweetFoundation
import UIKit

protocol SearchSelectionDelegate: class {

    func didSelectSearchResult(user: TokenUser)
    func isSearchResultSelected(user: TokenUser) -> Bool
}

extension SearchSelectionDelegate {
    func isSearchResultSelected(user: TokenUser) -> Bool { return false }
}

class BrowseSearchResultView: UITableView {
    var isMultipleSelectionMode = false

    var searchResults: [TokenUser] = [] {
        didSet {
            reloadData()
        }
    }

    weak var searchDelegate: SearchSelectionDelegate?

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect, style: UITableViewStyle) {
        super.init(frame: frame, style: style)

        backgroundColor = Theme.viewBackgroundColor

        dataSource = self
        delegate = self
        separatorStyle = .none
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = true

        register(ProfileCell.self)
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }
}

extension BrowseSearchResultView: UITableViewDelegate {

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = searchResults.element(at: indexPath.row) else { return }

        searchDelegate?.didSelectSearchResult(user: item)
        reloadData()
    }
}

extension BrowseSearchResultView: UITableViewDataSource {
	
    func tableView(_: UITableView, estimatedHeightForRowAt _: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        return searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeue(ProfileCell.self, for: indexPath)

        guard let profile = searchResults.element(at: indexPath.row) else {
            assertionFailure("Could not get profile at indexPath: \(indexPath)")
            return cell
        }

        cell.avatarPath = profile.avatarPath
        cell.name = profile.name
        cell.displayUsername = profile.isApp ? profile.category : profile.username

        if isMultipleSelectionMode {
            cell.selectionStyle = .none
            cell.isCheckmarkShowing = true
            cell.isCheckmarkChecked = searchDelegate?.isSearchResultSelected(user: profile) ?? false
        }

        return cell
    }
}
