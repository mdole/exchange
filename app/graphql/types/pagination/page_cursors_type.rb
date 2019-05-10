class Types::Pagination::PageCursorsType < Types::BaseObject
  field :first,
        Types::Pagination::PageCursorType,
        'optional, may be included in field around',
        null: true
  field :last,
        Types::Pagination::PageCursorType,
        'optional, may be included in field around',
        null: true
  field :around, [Types::Pagination::PageCursorType], null: false
  field :previous, Types::Pagination::PageCursorType, null: true
end
