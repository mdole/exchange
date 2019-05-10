ActiveAdmin.register AdminNote do
  belongs_to :order
  permit_params :order_id, :admin_id, :note_type, :description

  form do |f|
    f.inputs do
      f.input :order_id,
              as: :string, input_html: { readonly: true, value: order.id }
      f.input :admin_id,
              input_html: { readonly: true, value: current_user[:id] }
      f.input :note_type,
              as: :select,
              collection:
                AdminNote::TYPES.collect { |type| [type[1].humanize, type[0]] }
      f.input :description
    end
    f.actions
  end
end
