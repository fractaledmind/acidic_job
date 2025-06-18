Rails.application.routes.draw do
  mount AcidicJob::Engine => "/acidic_job"
end
